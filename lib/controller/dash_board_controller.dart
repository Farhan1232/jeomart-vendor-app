import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vendor/app/Home_screen/home_screen.dart';
import 'package:vendor/app/dine_in_order_screen/dine_in_order_screen.dart';
import 'package:vendor/app/product_screens/product_list_screen.dart';
import 'package:vendor/app/profile_screen/profile_screen.dart';
import 'package:vendor/app/wallet_screen/wallet_screen.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/models/section_model.dart';
import 'package:vendor/models/tax_model.dart';
import 'package:vendor/models/vendor_model.dart';
import 'package:vendor/utils/fire_store_utils.dart';

class DashBoardController extends GetxController {
  RxBool isLoading = true.obs;
  RxInt selectedIndex = 0.obs;
  RxList<NavigationItem> navigationItems = <NavigationItem>[].obs;

  RxList pageList = [].obs;
  Rx<VendorModel> vendorModel = VendorModel().obs;
  Rx<SectionModel> sectionModel = SectionModel().obs;

  @override
  void onInit() {
    // TODO: implement onInit

    getVendor();

    super.onInit();
  }

  void setPage() {
    final baseItems = <NavigationItem>[
      const NavigationItem(label: "Home", iconPath: "assets/icons/ic_home_cab.svg", page: HomeScreen()),
      if (sectionModel.value.dineInActive != null && sectionModel.value.dineInActive == true)
        NavigationItem(label: "Dine in", iconPath: "assets/icons/ic_dinein.svg", page: const DineInOrderScreen(), permissionModule: "Dine in Request"),
      NavigationItem(label: "Products", iconPath: "assets/icons/ic_menu.svg", page: const ProductListScreen(), permissionModule: "Manage Products"),
      NavigationItem(label: "Wallet", iconPath: "assets/icons/ic_wallet.svg", page: const WalletScreen(), permissionModule: "Wallet"),
      const NavigationItem(label: "Profile", iconPath: "assets/icons/ic_profile.svg", page: ProfileScreen()),
    ];
    // filter by permission
    navigationItems.value = baseItems.where((item) {
      log("SetPage :: ${item.label} :: ${item.permissionModule}");
      if (item.permissionModule == null) return true;
      return Constant.getEmployeeRolePermission(module: item.permissionModule!) == true;
    }).toList();
  }

  /// Loads what the bottom bar needs before the first tab is shown.
  ///
  /// The reads here used to run strictly one after another - store, store's
  /// section, the device geocoder plus the tax query, then the user's section -
  /// and the whole app sat on a spinner for their sum. Only two of them really
  /// depend on something: the store's section and the tax list both need the
  /// store. So the user's section is started straight away, the store's section
  /// and the taxes start together as soon as the store arrives, and the screen
  /// waits for the slowest instead of the total.
  ///
  /// Every result is still applied in the original order, so the final
  /// `sectionModel` / `Constant.selectedSection` are exactly what they were: the
  /// user's section wins when it exists.
  Future<void> getVendor() async {
    final Future<SectionModel?> userSectionRead = FireStoreUtils.getSectionById(Constant.userModel!.sectionId.toString());

    if (Constant.userModel?.vendorID != null) {
      Future<SectionModel?>? vendorSectionRead;
      await FireStoreUtils.getVendorById(Constant.userModel!.vendorID.toString(), allowRecent: true).then((value) {
        if (value != null) {
          vendorModel.value = value;
          Constant.vendorAdminCommission = value.adminCommission;
          vendorSectionRead = FireStoreUtils.getSectionById(vendorModel.value.sectionId.toString());
        }
      });
      Future<List<TaxModel>?>? taxRead;
      if (vendorModel.value.latitude != null && vendorModel.value.longitude != null) {
        taxRead = _readTaxList();
      }
      if (vendorSectionRead != null) {
        await vendorSectionRead!.then((value) {
          if (value != null) {
            sectionModel.value = value;
            Constant.selectedSection = sectionModel.value;
          }
        });
      }
      if (taxRead != null) {
        await taxRead.then((value) {
          if (value != null) {
            Constant.taxProductList = value.where((TaxModel taxModel) => taxModel.scope == "product").toList();
          }
        });
      }
    }

    await userSectionRead.then((value) {
      if (value != null) {
        sectionModel.value = value;
        Constant.selectedSection = sectionModel.value;
      } else {
        sectionModel.value = SectionModel();
      }
    });
    setPage();

    isLoading.value = false;
  }

  /// The store's product taxes, or `null` when they could not be looked up.
  ///
  /// `getTaxList` asks the phone's geocoder for the store's country first, and
  /// the geocoder throws when it is offline or unavailable (and on an empty
  /// answer). Nothing caught that, so [getVendor] stopped before
  /// `isLoading = false` and the whole app stayed on its spinner for the rest of
  /// the session. The tax list is left as it was in that case, and the app
  /// opens.
  Future<List<TaxModel>?> _readTaxList() async {
    try {
      return await FireStoreUtils.getTaxList(double.parse("${vendorModel.value.latitude}"), double.parse("${vendorModel.value.longitude}"), vendorModel.value.sectionId.toString());
    } catch (e) {
      log("DashBoardController: tax list not loaded :: $e");
      return null;
    }
  }

  DateTime? currentBackPressTime;
  RxBool canPopNow = false.obs;
}

class NavigationItem {
  final String label;
  final String iconPath;
  final Widget page;
  final String? permissionModule;

  const NavigationItem({required this.label, required this.iconPath, required this.page, this.permissionModule});
}
