import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor/utils/app_image_cache.dart';
import 'package:vendor/utils/concurrent.dart';

/// Session 35: the image cache's freshness floor and decode bound, and the
/// helper used to start independent reads together.
void main() {
  group('AppImageCache.freshnessFor', () {
    final DateTime now = DateTime(2026, 9, 13, 12);

    test("Storage's max-age=0 (valid until now) is raised to a week", () {
      expect(AppImageCache.freshnessFor(now, now: now), now.add(const Duration(days: 7)));
      expect(AppImageCache.freshnessFor(now.subtract(const Duration(minutes: 1)), now: now), now.add(const Duration(days: 7)));
    });

    test('a real future max-age from the server is kept as it is', () {
      final DateTime serverSays = now.add(const Duration(hours: 3));
      expect(AppImageCache.freshnessFor(serverSays, now: now), serverSays);
    });
  });

  group('AppImageCache.decodeWidthFor', () {
    test('fitWidth - the widget default - decodes at the drawn width in physical pixels', () {
      expect(AppImageCache.decodeWidthFor(width: 40, fit: BoxFit.fitWidth, devicePixelRatio: 3), 120);
      expect(AppImageCache.decodeWidthFor(width: 40, fit: null, devicePixelRatio: 3), 120);
      expect(AppImageCache.decodeWidthFor(width: 33.4, fit: BoxFit.fitWidth, devicePixelRatio: 2.625), 88);
    });

    test('contain and scaleDown never draw wider than the widget, so they are bounded too', () {
      expect(AppImageCache.decodeWidthFor(width: 100, fit: BoxFit.contain, devicePixelRatio: 2), 200);
      expect(AppImageCache.decodeWidthFor(width: 100, fit: BoxFit.scaleDown, devicePixelRatio: 2), 200);
    });

    test('fits that can draw a photo wider than the widget are decoded at full size, as before', () {
      // A wide photo in a square `cover` box is drawn several times wider than
      // the box; decoding it to the box width would blur it.
      for (final BoxFit fit in <BoxFit>[BoxFit.cover, BoxFit.fill, BoxFit.fitHeight, BoxFit.none]) {
        expect(AppImageCache.decodeWidthFor(width: 42, fit: fit, devicePixelRatio: 3), isNull, reason: '$fit');
      }
    });

    test('no bound without a real width', () {
      expect(AppImageCache.decodeWidthFor(width: null, fit: BoxFit.fitWidth, devicePixelRatio: 3), isNull);
      expect(AppImageCache.decodeWidthFor(width: double.infinity, fit: BoxFit.fitWidth, devicePixelRatio: 3), isNull);
      expect(AppImageCache.decodeWidthFor(width: 0, fit: BoxFit.fitWidth, devicePixelRatio: 3), isNull);
    });

    test('a nonsensical pixel ratio is treated as 1', () {
      expect(AppImageCache.decodeWidthFor(width: 50, fit: BoxFit.fitWidth, devicePixelRatio: 0), 50);
    });
  });

  group('Concurrent.start', () {
    test('control: a failing read nobody is awaiting yet IS reported as uncaught', () async {
      final List<Object> uncaught = <Object>[];
      await runZonedGuarded(() async {
        final Future<int> read = Future<int>.error(StateError('offline'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await expectLater(read, throwsA(isA<StateError>()));
      }, (Object error, StackTrace stack) => uncaught.add(error));
      expect(uncaught, isNotEmpty, reason: 'without this the next test proves nothing');
    });

    test('a read started early does not report its failure as uncaught, and still throws where it is awaited', () async {
      final List<Object> uncaught = <Object>[];
      await runZonedGuarded(() async {
        final Future<int> read = Concurrent.start(Future<int>.error(StateError('offline')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await expectLater(read, throwsA(isA<StateError>()));
      }, (Object error, StackTrace stack) => uncaught.add(error));
      expect(uncaught, isEmpty);
    });

    test('reads started together and applied in order stop at the first failure, like the sequential code did', () async {
      // The shape of getPaymentSettingsData / add product / store details: all
      // reads start at once, results are applied one by one in the old order.
      final List<String> applied = <String>[];
      final Future<String> first = Concurrent.start(Future<String>.delayed(const Duration(milliseconds: 30), () => 'payFast'));
      final Future<String> second = Concurrent.start(Future<String>.error(StateError('MercadoPago unreadable')));
      final Future<String> third = Concurrent.start(Future<String>.value('paypal'));

      Future<void> applyAll() async {
        applied.add(await first);
        applied.add(await second);
        applied.add(await third);
      }

      await expectLater(applyAll(), throwsA(isA<StateError>()));
      expect(applied, <String>['payFast']);
    });

    test('independent reads overlap instead of queuing', () async {
      final Stopwatch watch = Stopwatch()..start();
      final Future<void> a = Concurrent.start(Future<void>.delayed(const Duration(milliseconds: 120)));
      final Future<void> b = Concurrent.start(Future<void>.delayed(const Duration(milliseconds: 120)));
      await a;
      await b;
      expect(watch.elapsedMilliseconds, lessThan(220));
    });
  });
}
