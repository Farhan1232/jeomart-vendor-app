import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor/utils/recent_doc_cache.dart';

/// Session 35: the short-lived memo behind `getVendorById(allowRecent: true)`
/// and `getSectionById`.
void main() {
  const Duration window = Duration(seconds: 15);

  setUp(RecentDocCache.clear);

  test('a second read inside the window is served without loading again', () async {
    var loads = 0;
    Future<Map<String, dynamic>?> load() async {
      loads++;
      return <String, dynamic>{'title': 'Store'};
    }

    final a = await RecentDocCache.read('vendors/v1', load, ttl: window);
    final b = await RecentDocCache.read('vendors/v1', load, ttl: window);

    expect(loads, 1);
    expect(a, <String, dynamic>{'title': 'Store'});
    expect(b, <String, dynamic>{'title': 'Store'});
  });

  test('callers arriving while a read is in flight share that one read', () async {
    var loads = 0;
    final gate = Completer<Map<String, dynamic>?>();
    Future<Map<String, dynamic>?> load() {
      loads++;
      return gate.future;
    }

    final first = RecentDocCache.read('vendors/v1', load, ttl: window);
    final second = RecentDocCache.read('vendors/v1', load, ttl: window);
    gate.complete(<String, dynamic>{'a': 1});

    expect(await first, <String, dynamic>{'a': 1});
    expect(await second, <String, dynamic>{'a': 1});
    expect(loads, 1);
  });

  test('every caller gets its own copy, so one screen editing its model cannot change the next', () async {
    Future<Map<String, dynamic>?> load() async => <String, dynamic>{
      'photos': <dynamic>['a.png'],
      'filters': <String, dynamic>{'Wifi': 'Yes'},
    };

    final first = await RecentDocCache.read('vendors/v1', load, ttl: window);
    // VendorModel.fromJson keeps these lists and maps by reference, and the
    // store screens do add to them.
    (first!['photos'] as List).add('b.png');
    (first['filters'] as Map)['Wifi'] = 'No';
    first['title'] = 'changed';

    final second = await RecentDocCache.read('vendors/v1', load, ttl: window);
    expect(second!['photos'], <dynamic>['a.png']);
    expect((second['filters'] as Map)['Wifi'], 'Yes');
    expect(second.containsKey('title'), isFalse);
  });

  test('a copy keeps the collection types the models check for and shares immutable leaves', () {
    final DateTime leaf = DateTime(2026, 9, 13);
    final Map<String, dynamic> source = <String, dynamic>{
      'g': <String, dynamic>{'geohash': 'tt3'},
      'categoryID': <dynamic>['c1'],
      'createdAt': leaf,
      'nested': <String, dynamic>{
        'list': <dynamic>[
          <String, dynamic>{'x': 1},
        ],
      },
    };

    final copy = RecentDocCache.deepCopyMap(source);

    expect(copy, source);
    expect(copy['g'], isA<Map<String, dynamic>>());
    expect(copy['categoryID'], isA<List<dynamic>>());
    expect(copy['categoryID'] is String, isFalse);
    expect(identical(copy['createdAt'], leaf), isTrue);
    expect(identical(copy['g'], source['g']), isFalse);
    expect(identical((copy['nested'] as Map)['list'], (source['nested'] as Map)['list']), isFalse);
  });

  test('a missing document is not remembered', () async {
    var loads = 0;
    Future<Map<String, dynamic>?> load() async {
      loads++;
      return null;
    }

    expect(await RecentDocCache.read('sections/none', load, ttl: window), isNull);
    expect(await RecentDocCache.read('sections/none', load, ttl: window), isNull);
    expect(loads, 2);
  });

  test('a failed read reaches the caller and is not remembered', () async {
    var loads = 0;
    Future<Map<String, dynamic>?> load() async {
      loads++;
      if (loads == 1) throw StateError('offline');
      return <String, dynamic>{'ok': true};
    }

    await expectLater(RecentDocCache.read('vendors/v1', load, ttl: window), throwsA(isA<StateError>()));
    expect(await RecentDocCache.read('vendors/v1', load, ttl: window), <String, dynamic>{'ok': true});
    expect(loads, 2);
  });

  test('the window expires', () async {
    var loads = 0;
    Future<Map<String, dynamic>?> load() async {
      loads++;
      return <String, dynamic>{'n': loads};
    }

    await RecentDocCache.read('vendors/v1', load, ttl: const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(await RecentDocCache.read('vendors/v1', load, ttl: const Duration(milliseconds: 1)), <String, dynamic>{'n': 2});
  });

  test('a write drops the copy', () async {
    var loads = 0;
    Future<Map<String, dynamic>?> load() async {
      loads++;
      return <String, dynamic>{'n': loads};
    }

    await RecentDocCache.read('vendors/v1', load, ttl: window);
    expect(RecentDocCache.isFresh('vendors/v1'), isTrue);
    RecentDocCache.invalidate('vendors/v1');
    expect(RecentDocCache.isFresh('vendors/v1'), isFalse);
    expect(await RecentDocCache.read('vendors/v1', load, ttl: window), <String, dynamic>{'n': 2});
  });

  test('a write during an in-flight read stops that pre-write value from being remembered', () async {
    var loads = 0;
    final gate = Completer<Map<String, dynamic>?>();
    Future<Map<String, dynamic>?> load() {
      loads++;
      return loads == 1 ? gate.future : Future<Map<String, dynamic>?>.value(<String, dynamic>{'v': 'after write'});
    }

    final inFlight = RecentDocCache.read('vendors/v1', load, ttl: window);
    RecentDocCache.invalidate('vendors/v1');
    gate.complete(<String, dynamic>{'v': 'before write'});

    // The caller that asked before the write still gets its answer...
    expect(await inFlight, <String, dynamic>{'v': 'before write'});
    // ...but the next screen reads again instead of seeing the stale copy.
    expect(await RecentDocCache.read('vendors/v1', load, ttl: window), <String, dynamic>{'v': 'after write'});
    expect(loads, 2);
  });
}
