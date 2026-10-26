import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor/service/audio_player_service.dart';

/// Source with comments removed, so an assertion can never be satisfied by the
/// explanatory comments that quote the old code.
String code(String path) {
  final String source = File(path).readAsStringSync();
  return source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAllMapped(RegExp(r'(^|\s)//.*$', multiLine: true), (Match m) => m[1]!);
}

/// The text of the method starting at [signature], up to the next member.
String method(String source, String signature) {
  final int start = source.indexOf(signature);
  expect(start, isNot(-1), reason: 'missing: $signature');
  final int end = source.indexOf(RegExp(r'\n  (Future<|static |void |bool |Widget |InkWell |Dialog |@override)'), start + signature.length);
  return source.substring(start, end == -1 ? source.length : end);
}

void main() {
  group('launch', () {
    test('App Check and the preferences start together before the first frame', () {
      final String main = code('lib/main.dart');
      final int wait = main.indexOf('await Future.wait<void>([');
      expect(wait, isNot(-1));
      final String together = main.substring(wait, main.indexOf(']);', wait));
      expect(together.contains('FirebaseAppCheck.instance.activate('), isTrue);
      expect(together.contains('Preferences.initPref()'), isTrue);
      expect(main.contains('await Preferences.initPref();'), isFalse);
      // Both still finish before the theme controller, which reads a preference.
      expect(main.indexOf('Get.put(ThemeController());'), greaterThan(wait));
    });

    test('the maintenance and login reads start with the splash, not after the settings wait', () {
      final String splash = code('lib/controller/splash_controller.dart');
      final String boot = method(splash, 'Future<void> _boot()');
      final int maintenance = boot.indexOf('_maintenanceRead = Concurrent.start(FireStoreUtils.isMaintenanceMode());');
      final int login = boot.indexOf('_loginRead = Concurrent.start(FireStoreUtils.isLogin());');
      final int settingsWait = boot.indexOf('GlobalSettingController.settingsReady');
      expect(maintenance, isNot(-1));
      expect(login, isNot(-1));
      expect(maintenance, lessThan(settingsWait));
      expect(login, lessThan(settingsWait));
    });

    test('the splash still decides maintenance, then onboarding, then sign-in, and a retry reads again', () {
      final String redirect = method(code('lib/controller/splash_controller.dart'), 'Future<void> redirectScreen()');
      final int maintenance = redirect.indexOf('if (await maintenanceRead == true)');
      final int onboarding = redirect.indexOf('Preferences.isFinishOnBoardingKey');
      final int login = redirect.indexOf('await (loginRead ?? FireStoreUtils.isLogin())');
      expect(maintenance, isNot(-1));
      expect(onboarding, greaterThan(maintenance));
      expect(login, greaterThan(onboarding));
      // The early reads belong to the first attempt only.
      expect(redirect.indexOf('_maintenanceRead = null;'), lessThan(maintenance));
      expect(redirect.indexOf('_loginRead = null;'), lessThan(maintenance));
      expect(redirect.contains('_maintenanceRead ?? FireStoreUtils.isMaintenanceMode()'), isTrue);
    });
  });

  group('settings', () {
    late String body;
    setUp(() => body = method(code('lib/utils/fire_store_utils.dart'), 'static Future<void> getSettings()'));

    test('each read applies the device copy first and only waits for the server when there is none', () {
      final int cache = body.indexOf('doc.get(const GetOptions(source: Source.cache))');
      final int server = body.indexOf('await apply(await doc.get());');
      expect(cache, isNot(-1));
      expect(server, greaterThan(cache));
      expect(body.contains('if (!servedFromDevice) await fromServer;'), isTrue);
      expect(body.contains('await Future.wait<void>(firstPass)'), isTrue);
    });

    test('only the two deciding documents still wait for the server', () {
      final List<String> serverFirst = <String>[
        for (final RegExpMatch m in RegExp(r'read\("(\w+)",((?:(?!read\(")[\s\S])*?)\}, deviceFirst: false\);').allMatches(body)) m[1]!,
      ];
      expect(serverFirst, <String>['vendor', 'document_verification_settings']);
      expect(RegExp(r'deviceFirst: false').allMatches(body).length, 2);
    });

    test('every document is still read with its original fields', () {
      expect(RegExp(r'\bread\("').allMatches(body).length, 14);
      expect(RegExp(r'\blisten\("').allMatches(body).length, 3);
      for (final String name in <String>[
        'globalSettings', 'DriverNearBy', 'scheduleOrderNotification', 'vendor', 'story', 'placeHolderImage', 'specialDiscountOffer',
        'emailSetting', 'ContactUs', 'document_verification_settings', 'privacyPolicy', 'openai_settings', 'termsAndConditions', 'digitalProduct',
      ]) {
        expect(body.contains('read("$name", ('), isTrue, reason: name);
      }
    });

    test('the audio player is still created once per launch although globalSettings can be applied twice', () {
      final String global = body.substring(body.indexOf('read("globalSettings"'), body.indexOf('read("DriverNearBy"'));
      final int guard = global.indexOf('if (!audioInitialised) {');
      final int init = global.indexOf('await AudioPlayerService.initAudio();');
      expect(guard, isNot(-1));
      expect(init, greaterThan(guard));
      expect(global.indexOf('audioInitialised = true;'), inInclusiveRange(guard, init));
      expect(RegExp(r'initAudio\(').allMatches(body).length, 1);
      expect(global.contains('unawaited(AudioPlayerService.prepareRingtone(Constant.orderRingtoneUrl));'), isTrue);
    });
  });

  group('new-order ringtone', () {
    const String url = 'https://firebasestorage.example/ringtone.mp3';
    tearDown(AudioPlayerService.forgetRingtone);

    test('is streamed until a copy is on the phone, then played from the copy', () async {
      expect(AudioPlayerService.ringtoneSource(url), isA<UrlSource>());
      await AudioPlayerService.prepareRingtone(url, download: (String u) async => '/data/ringtone.mp3');
      final Source source = AudioPlayerService.ringtoneSource(url);
      expect(source, isA<DeviceFileSource>());
      expect((source as DeviceFileSource).path, '/data/ringtone.mp3');
    });

    test('a different ringtone URL is streamed, never played from the old copy', () async {
      await AudioPlayerService.prepareRingtone(url, download: (String u) async => '/data/ringtone.mp3');
      final Source other = AudioPlayerService.ringtoneSource('https://firebasestorage.example/new.mp3');
      expect(other, isA<UrlSource>());
      expect((other as UrlSource).url, 'https://firebasestorage.example/new.mp3');
    });

    test('a failed or empty download leaves it streamed, as before', () async {
      await AudioPlayerService.prepareRingtone(url, download: (String u) async => throw Exception('offline'));
      expect(AudioPlayerService.ringtoneSource(url), isA<UrlSource>());
      int calls = 0;
      await AudioPlayerService.prepareRingtone('', download: (String u) async {
        calls++;
        return '/x';
      });
      expect(calls, 0);
    });

    test('a copy is downloaded once, and playing still loops the same URL', () async {
      int calls = 0;
      Future<String> download(String u) async {
        calls++;
        return '/data/ringtone.mp3';
      }

      await AudioPlayerService.prepareRingtone(url, download: download);
      await AudioPlayerService.prepareRingtone(url, download: download);
      expect(calls, 1);

      final String play = method(code('lib/service/audio_player_service.dart'), 'static Future<void> playSound(bool isPlay)');
      expect(play.contains('await _audioPlayer.setSource(ringtoneSource(url));'), isTrue);
      expect(play.contains('await _audioPlayer.setReleaseMode(ReleaseMode.loop);'), isTrue);
      expect(play.contains('UrlSource('), isFalse);
    });
  });
}
