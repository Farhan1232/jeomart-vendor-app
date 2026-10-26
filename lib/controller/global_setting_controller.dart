import 'dart:async';
import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/models/currency_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/utils/fire_store_utils.dart';
import 'package:vendor/utils/notification_service.dart';

import '../constant/collection_name.dart';

class GlobalSettingController extends GetxController {
  /// Completes when the first pass of the settings has arrived: every
  /// `settings/*` document [FireStoreUtils.getSettings] reads, and the active
  /// currency.
  ///
  /// The splash screen waits on this instead of sleeping for a fixed three
  /// seconds. That timer was a guess at how long these reads take - too long on
  /// a good connection, and on a slow one the app built its first screens with
  /// `Constant` still at its compile-time defaults (the currency every amount on
  /// the order cards is formatted with, the app colour, the subscription
  /// switch).
  ///
  /// Static because the splash controller needs it without holding the
  /// instance, and because the first pass only happens once per launch.
  static final Completer<void> _settingsReady = Completer<void>();

  static Future<void> get settingsReady => _settingsReady.future;

  /// Firestore listeners opened by this controller.
  ///
  /// They used to run for the rest of the session because nothing cancelled
  /// them when the screen closed, and re-entering the screen opened another
  /// set on top.
  final List<StreamSubscription<dynamic>> _subscriptions = <StreamSubscription<dynamic>>[];

  @override
  void onClose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.onClose();
  }

  @override
  void onInit() {
    notificationInit();
    getCurrentCurrency();

    super.onInit();
  }

  Future<void> getCurrentCurrency() async {
    final Completer<void> currencyDelivered = Completer<void>();
    _subscriptions.add(
      FireStoreUtils.fireStore
          .collection(CollectionName.currencies)
          .where("isActive", isEqualTo: true)
          .snapshots()
          .listen(
            (event) {
              try {
                if (event.docs.isNotEmpty) {
                  Constant.currencyModel = CurrencyModel.fromJson(event.docs.first.data());
                } else {
                  Constant.currencyModel = CurrencyModel(id: "", code: "USD", decimalDigits: 2, enable: true, name: "US Dollar", symbol: "\$", symbolAtRight: false);
                }
              } finally {
                if (!currencyDelivered.isCompleted) currencyDelivered.complete();
              }
            },
            onError: (Object e) {
              log("GlobalSettingController: currency listener :: $e");
              if (!currencyDelivered.isCompleted) currencyDelivered.complete();
            },
          ),
    );
    try {
      await Future.wait<void>([currencyDelivered.future, FireStoreUtils.getSettings()]);
    } finally {
      // In a `finally`: settings that could not be read must still release the
      // splash screen (which also caps its own wait).
      if (!_settingsReady.isCompleted) _settingsReady.complete();
    }
  }

  NotificationService notificationService = NotificationService();

  dynamic notificationInit() => notificationService.initInfo().then((value) async {
    String token = await NotificationService.getToken();
    if (FirebaseAuth.instance.currentUser != null) {
      await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((value) {
        if (value != null) {
          UserModel driverUserModel = value;
          driverUserModel.fcmToken = token;
          FireStoreUtils.updateUser(driverUserModel);
        }
      });
    }
  });
}
