import 'dart:async';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:vendor/app/auth_screen/login_screen.dart';
import 'package:vendor/app/dash_board_screens/app_not_access_screen.dart';
import 'package:vendor/app/dash_board_screens/dash_board_screen.dart';
import 'package:vendor/app/maintenance_mode_screen/maintenance_mode_screen.dart';
import 'package:vendor/app/on_boarding_screen.dart';
import 'package:vendor/app/subscription_plan_screen/subscription_plan_screen.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/controller/global_setting_controller.dart';
import 'package:vendor/models/section_model.dart';
import 'package:vendor/models/vendor_model.dart';
import 'package:vendor/utils/concurrent.dart';
import 'package:vendor/utils/fire_store_utils.dart';
import 'package:vendor/utils/notification_service.dart';
import 'package:vendor/utils/preferences.dart';

class SplashController extends GetxController {
  /// The shortest time the splash art stays up, so a warm start does not flash
  /// past it.
  static const Duration _minimumSplash = Duration(milliseconds: 800);

  /// Hard cap on waiting for `settings/*`. Past this the app carries on, which
  /// is what the old fixed timer did on every launch.
  static const Duration _settingsWait = Duration(seconds: 6);

  /// Hard cap on waiting for the push token to be saved before opening the app.
  ///
  /// A Firestore write only completes when the server acknowledges it, so with
  /// no connection the old `await updateUser(...)` never returned and the app
  /// sat on the splash art for good. The write itself is not cancelled - it is
  /// queued and still reaches the server once there is a connection.
  static const Duration _tokenSaveWait = Duration(seconds: 8);

  /// How many times a failed [redirectScreen] is tried before giving up.
  static const int _attempts = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Set by every navigation [redirectScreen] makes.
  bool _navigated = false;

  @override
  void onInit() {
    super.onInit();
    unawaited(_boot());
  }

  /// Replaces `Timer(const Duration(seconds: 3), () => redirectScreen())`.
  ///
  /// That timer cost every launch three seconds of doing nothing, spent
  /// *before* [redirectScreen] started its own chain of network reads, so
  /// startup cost three seconds **plus** the work. It was also only a guess at
  /// how long the settings take: on a slow connection the app could still leave
  /// the splash before `settings/vendor` had arrived, and the subscription check
  /// below would read a default.
  ///
  /// The minimum splash time and the settings load now run together, and every
  /// wait is bounded. The same Session 8 change was made to the customer and
  /// driver apps; the vendor app had not had it.
  Future<void> _boot() async {
    final Future<void> minimumSplash = Future<void>.delayed(_minimumSplash);
    _maintenanceRead = Concurrent.start(FireStoreUtils.isMaintenanceMode());
    _loginRead = Concurrent.start(FireStoreUtils.isLogin());
    try {
      await GlobalSettingController.settingsReady.timeout(_settingsWait);
    } catch (e) {
      log('splash: carrying on without every setting :: $e');
    }
    await minimumSplash;

    for (int attempt = 1; attempt <= _attempts; attempt++) {
      try {
        await redirectScreen();
        if (!_navigated) {
          // Two branches below choose no screen at all - a signed-in uid whose
          // `users` document is gone, and an employee whose store's plan has
          // lapsed. Both used to leave the app on the splash art for ever. The
          // login flow does not let either of them in, so they land where the
          // login flow leaves them.
          log('splash: no screen was chosen for this account');
          await _signOutTo(const LoginScreen());
        }
        return;
      } catch (e, s) {
        log('splash: redirect attempt $attempt failed :: $e', stackTrace: s);
        if (_navigated) return;
        // Nothing caught these before, so one failed read left the app on the
        // splash art with no way forward. A dropped connection usually recovers
        // within a retry or two, which keeps the vendor signed in.
        if (attempt < _attempts) await Future<void>.delayed(_retryDelay);
      }
    }
    await _signOutTo(const LoginScreen());
  }

  void _go(dynamic page) {
    _navigated = true;
    Get.offAll(page);
  }

  Future<void> _signOutTo(dynamic page) async {
    await FirebaseAuth.instance.signOut();
    _go(page);
  }

  /// Fetches the push token and saves it on the signed-in user, as before -
  /// the token fetch and the write still happen in this order and are still
  /// awaited - but bounded by [_tokenSaveWait] so that no connection no longer
  /// means no way past the splash screen.
  Future<void> _saveFcmToken() async {
    Future<void> save() async {
      Constant.userModel?.fcmToken = await NotificationService.getToken();
      await FireStoreUtils.updateUser(Constant.userModel!);
    }

    await save().timeout(
      _tokenSaveWait,
      onTimeout: () {
        log('splash: push token not saved yet; the write stays queued');
      },
    );
  }

  /// The two reads [redirectScreen] opens with, started by [_boot] the moment
  /// the splash appears rather than after the settings wait and the minimum
  /// splash time.
  ///
  /// Both are plain reads that decide nothing by themselves: [redirectScreen]
  /// still asks "maintenance?" first, then checks onboarding, then "signed
  /// in?", and acts on the answers in that order. Starting them early only
  /// means the answers are usually already here when it asks. Each is used by
  /// the first attempt only; a retry reads again, as before. (The customer and
  /// driver splash screens have done this since Session 36.)
  Future<bool>? _maintenanceRead;
  Future<bool>? _loginRead;

  Future<void> redirectScreen() async {
    final Future<bool> maintenanceRead = _maintenanceRead ?? FireStoreUtils.isMaintenanceMode();
    final Future<bool>? loginRead = _loginRead;
    _maintenanceRead = null;
    _loginRead = null;

    if (await maintenanceRead == true) {
      _go(() => MaintenanceModeScreen());
      return;
    } else {
      if (Preferences.getBoolean(Preferences.isFinishOnBoardingKey) == false) {
        _go(const OnboardingScreen());
      } else {
        bool isLogin = await (loginRead ?? FireStoreUtils.isLogin());
        if (isLogin == true) {
          await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((value) async {
            if (value != null) {
              Constant.userModel = value;
              if (Constant.userModel?.role == Constant.userRoleVendor) {
                if (Constant.userModel?.active == true) {
                  // The section read does not depend on the token save, so it
                  // is started first and runs alongside it instead of after it.
                  // Its result is still applied at the same point as before.
                  Future<SectionModel?>? sectionRead;
                  if (value.sectionId != null || value.sectionId!.isNotEmpty) {
                    sectionRead = FireStoreUtils.getSectionById(value.sectionId.toString());
                  }
                  await _saveFcmToken();
                  // VendorModel? vendor = await FireStoreUtils.getVendorById(Constant.userModel!.vendorID!);
                  bool isPlanExpire = false;

                  if (Constant.userModel?.subscriptionPlan?.id != null) {
                    if (Constant.userModel?.subscriptionExpiryDate == null) {
                      if (Constant.userModel?.subscriptionPlan?.expiryDay == '-1') {
                        isPlanExpire = false;
                      } else {
                        isPlanExpire = true;
                      }
                    } else {
                      DateTime expiryDate = Constant.userModel!.subscriptionExpiryDate!.toDate();
                      isPlanExpire = expiryDate.isBefore(DateTime.now());
                    }
                  } else {
                    isPlanExpire = true;
                  }

                  if (sectionRead != null) {
                    await sectionRead.then((value) {
                      if (value != null) {
                        Constant.selectedSection = value;
                      }
                    });
                  }

                  if (Constant.userModel?.subscriptionPlanId == null || isPlanExpire == true) {
                    if (Constant.userModel!.sectionId!.isEmpty && Constant.isSubscriptionModelApplied == false) {
                      _go(const DashBoardScreen());
                    } else {
                      _go(const SubscriptionPlanScreen());
                    }
                  } else if (Constant.userModel!.subscriptionPlan?.features?.ownerMobileApp == true) {
                    _go(const DashBoardScreen());
                  } else {
                    _go(const AppNotAccessScreen());
                  }
                } else {
                  await _signOutTo(const LoginScreen());
                }
              } else if (Constant.userModel?.role == Constant.userRoleEmployee) {
                if (Constant.userModel?.active == true) {
                  // The store and the section are independent of the token save
                  // and of each other, so all three run together. Each result is
                  // still used at the same point as before.
                  final Future<VendorModel?> vendorRead = FireStoreUtils.getVendorById(Constant.userModel!.vendorID!);
                  Future<SectionModel?>? sectionRead;
                  if (value.sectionId != null || value.sectionId!.isNotEmpty) {
                    sectionRead = FireStoreUtils.getSectionById(value.sectionId.toString());
                  }
                  await _saveFcmToken();
                  VendorModel? vendor = await vendorRead;
                  bool isPlanExpire = false;
                  if (vendor?.subscriptionPlan?.id != null) {
                    if (vendor?.subscriptionExpiryDate == null) {
                      if (vendor?.subscriptionPlan?.expiryDay == '-1') {
                        isPlanExpire = false;
                      } else {
                        isPlanExpire = true;
                      }
                    } else {
                      DateTime expiryDate = vendor!.subscriptionExpiryDate!.toDate();
                      isPlanExpire = expiryDate.isBefore(DateTime.now());
                    }
                  } else {
                    isPlanExpire = true;
                  }

                  if (sectionRead != null) {
                    await sectionRead.then((value) {
                      if (value != null) {
                        Constant.selectedSection = value;
                      }
                    });
                  }

                  if (vendor?.subscriptionPlanId == null || isPlanExpire == true) {
                    if (vendor!.sectionId!.isEmpty && Constant.isSubscriptionModelApplied == false) {
                      _go(const DashBoardScreen());
                    }
                  } else if (vendor!.subscriptionPlan?.features?.ownerMobileApp == true) {
                    _go(const DashBoardScreen());
                  } else {
                    _go(const AppNotAccessScreen());
                  }
                } else {
                  await _signOutTo(const LoginScreen());
                }
              } else {
                await _signOutTo(const LoginScreen());
              }
            }
          });
        } else {
          await _signOutTo(const LoginScreen());
        }
      }
    }
  }
}
