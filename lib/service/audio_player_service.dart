import 'dart:async';
import 'dart:developer';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vendor/utils/app_image_cache.dart';
import 'package:vendor/utils/preferences.dart';

class AudioPlayerService {
  static late AudioPlayer _audioPlayer;

  static Future<void> initAudio() async {
    _audioPlayer = AudioPlayer(playerId: "playerId");
  }

  /// The new-order ringtone, once a copy of it is on this phone.
  ///
  /// It used to be streamed from its URL every time a new order arrived. The
  /// player has to open a connection and buffer the file before the first note
  /// plays, and Firebase Storage serves it with `max-age=0`, so nothing kept a
  /// copy - on mobile data the order was on screen well before the vendor heard
  /// it. It is fetched once now, when the settings arrive, and played from the
  /// file. Same sound, same loop, same volume. (The driver app has done this
  /// since Session 43.)
  static String? _ringtoneUrl;
  static String? _ringtonePath;

  /// Keeps a copy of [url] on the device, ahead of the first order.
  ///
  /// Cheap to call again: a URL that already has a copy returns at once. A
  /// failed download only means the ringtone is streamed, as it always was.
  static Future<void> prepareRingtone(String url, {Future<String> Function(String url)? download}) async {
    if (url.isEmpty) return;
    if (url == _ringtoneUrl && _ringtonePath != null) return;
    try {
      final String path = await (download ?? _download)(url);
      _ringtoneUrl = url;
      _ringtonePath = path;
    } catch (e) {
      log('ringtone copy failed, it will be streamed :: $e');
    }
  }

  static Future<String> _download(String url) async => (await AppImageCache.manager.getSingleFile(url)).path;

  /// Where the ringtone for [url] is played from: the copy on the device when
  /// there is one, otherwise the URL itself.
  static Source ringtoneSource(String url) {
    final String? path = _ringtonePath;
    if (path != null && url == _ringtoneUrl) return DeviceFileSource(path);
    return UrlSource(url);
  }

  @visibleForTesting
  static void forgetRingtone() {
    _ringtoneUrl = null;
    _ringtonePath = null;
  }

  static Future<void> playSound(bool isPlay) async {
    try {
      if (isPlay) {
        if (_audioPlayer.state != PlayerState.playing) {
          final String url = Preferences.getString(Preferences.orderRingtone);
          log("PlaySound :: 11 :: $isPlay :: $url");
          await _audioPlayer.setSource(ringtoneSource(url));
          await _audioPlayer.setReleaseMode(ReleaseMode.loop);
          await _audioPlayer.resume();
          // An order that arrived before the copy was made is streamed; the
          // next one plays from the device.
          unawaited(prepareRingtone(url));
        }
      } else {
        if (_audioPlayer.state != PlayerState.stopped) {
          log("PlaySound :: 22 :: $isPlay :: ${Preferences.getString(Preferences.orderRingtone)}");
          await _audioPlayer.stop();
        }
      }
    } catch (e) {
      print("Error in playSound: $e");
    }
  }
}
