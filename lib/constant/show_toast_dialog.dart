import 'dart:async';
import 'dart:developer';

import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';

class ShowToastDialog {
  static void showToast(String? message, {EasyLoadingToastPosition position = EasyLoadingToastPosition.top}) {
    EasyLoading.showToast(message!.tr, toastPosition: position);
  }

  static void showToastDuration(String? message, {EasyLoadingToastPosition position = EasyLoadingToastPosition.top, required Duration duration}) {
    EasyLoading.showToast(message!.tr, toastPosition: position, duration: duration);
  }

  /// How long a blocking loader may stay on screen before it takes itself down.
  ///
  /// [showLoader] is called from 85 places in the vendor app that then `await`
  /// something - a Firestore write, the wallet transaction, a notification - and
  /// call [closeLoader] on the line after. Most of those are not inside a `try`,
  /// so **any** throw on the awaited call skips the close. The loader is
  /// configured with `userInteractions = false`, so what is left is a
  /// full-screen overlay that blocks every tap until the app is killed - from
  /// the outside, the app has frozen.
  ///
  /// Guarding all 85 call sites individually would mean editing every order,
  /// wallet and product flow. This does the same job in one place: the loader is
  /// a UI affordance, not state, so nothing is lost by putting a ceiling on how
  /// long it may block the screen. Same backstop as the customer and driver apps.
  static const Duration loaderWatchdog = Duration(seconds: 30);

  /// The ceiling for a loader shown over photo/video uploads, which can
  /// legitimately take minutes on mobile data. Lifting the overlay mid-upload
  /// would let the vendor press Save a second time, so those call sites pass
  /// `longRunning: true` and are only rescued from a loader that is truly stuck.
  static const Duration longLoaderWatchdog = Duration(minutes: 10);

  static Timer? _watchdog;

  static void showLoader(String message, {bool longRunning = false}) {
    final Duration limit = longRunning ? longLoaderWatchdog : loaderWatchdog;
    _watchdog?.cancel();
    _watchdog = Timer(limit, () {
      log('ShowToastDialog: loader "$message" was never closed after ${limit.inSeconds}s - dismissing it');
      EasyLoading.dismiss();
      _watchdog = null;
    });
    EasyLoading.show(status: message.tr);
  }

  static void closeLoader() {
    _watchdog?.cancel();
    _watchdog = null;
    EasyLoading.dismiss();
  }

  /// Test seam: whether a loader is currently being watched.
  static bool get hasPendingLoader => _watchdog != null;
}
