import 'package:get/get.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/models/dine_in_booking_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/models/vendor_model.dart';
import 'package:vendor/utils/fire_store_utils.dart';

class DineInOrderController extends GetxController {
  RxBool isLoading = true.obs;
  RxInt selectedTabIndex = 0.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getUserProfile();
    super.onInit();
  }

  Rx<UserModel> userModel = UserModel().obs;
  Rx<VendorModel> vendorModel = VendorModel().obs;

  RxList<DineInBookingModel> featureList = <DineInBookingModel>[].obs;
  RxList<DineInBookingModel> historyList = <DineInBookingModel>[].obs;

  Future<void> getUserProfile() async {
    await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((value) {
      if (value != null) {
        userModel.value = value;
      }
    });

    if (Constant.userModel!.vendorID != null && Constant.userModel!.vendorID!.isNotEmpty) {
      // The store and both booking lists are independent reads; they used to be
      // made one after another, so the tab waited for all three in a row.
      await Future.wait<void>([
        FireStoreUtils.getVendorById(Constant.userModel!.vendorID.toString(), allowRecent: true).then((value) {
          if (value != null) {
            vendorModel.value = value;
          }
        }),
        getDineBooking(),
      ]);
    }

    isLoading.value = false;
  }

  /// Upcoming and past bookings, read together rather than one after the other.
  Future<void> getDineBooking() async {
    await Future.wait<void>([
      FireStoreUtils.getDineInBooking(true).then((value) {
        featureList.value = value;
      }),
      FireStoreUtils.getDineInBooking(false).then((value) {
        historyList.value = value;
      }),
    ]);
  }
}
