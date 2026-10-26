import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/models/attributes_model.dart';
import 'package:vendor/models/product_model.dart';
import 'package:vendor/models/tax_model.dart';
import 'package:vendor/models/vendor_model.dart';
import 'package:vendor/utils/concurrent.dart';
import 'package:vendor/utils/fire_store_utils.dart';

class AdminProductController extends GetxController {
  RxBool isLoading = true.obs;

  // Rx<UserModel> userModel = UserModel().obs;
  Rx<VendorModel> vendorModel = VendorModel().obs;
  RxList<ProductModel> productList = <ProductModel>[].obs;
  RxList<ProductModel> allProductList = <ProductModel>[].obs;
  RxList<ProductModel> vendorProductList = <ProductModel>[].obs;

  var searchTextController = TextEditingController().obs;
  RxList<AttributesModel> attributesList = <AttributesModel>[].obs;
  RxList<TaxModel> taxList = <TaxModel>[].obs;

  @override
  void onInit() {
    // TODO: implement onInit
    taxList.value = Constant.taxProductList ?? [];
    getAdminProducts();
    super.onInit();
  }

  Future<void> getAdminProducts() async {
    // The attributes and the store's own products do not depend on the store
    // document, so they are started first and read alongside it. The admin
    // catalogue needs the store's section, so it still follows the store.
    final Future<void> attributesRead = Concurrent.start(
      FireStoreUtils.getAttributes().then((value) {
        if (value != null) {
          attributesList.value = value;
        }
      }),
    );
    final Future<void> vendorProductsRead = Concurrent.start(getVendorProduct());

    if (Constant.userModel?.vendorID != null && Constant.userModel?.vendorID?.isNotEmpty == true) {
      await FireStoreUtils.getVendorById(Constant.userModel!.vendorID.toString()).then((value) {
        if (value != null) {
          vendorModel.value = value;
        }
      });
    }

    final Future<void> adminProductsRead = Concurrent.start(
      FireStoreUtils.getAdminProduct(vendorModel.value.sectionId.toString()).then((products) {
        if (products != null) {
          allProductList.value = products;
        }
      }),
    );

    await attributesRead;
    await adminProductsRead;
    await vendorProductsRead;
    isLoading.value = false;
    update();
    onSearchTextChanged('');
  }

  Future<void> getVendorProduct() async {
    await FireStoreUtils.getProduct().then(
      (value) {
        if (value != null) {
          vendorProductList.value = value;
        }
      },
    );
  }

  /// The list is built first and handed over in one assignment. Clearing it and
  /// adding the matches one by one told the screen about every single product -
  /// the whole catalogue of the section, on every keystroke. (`assignAll` would
  /// still notify twice: it is a clear plus an add.) Same filter, same order,
  /// same result.
  void onSearchTextChanged(String text) {
    if (text.isEmpty) {
      productList.value = allProductList.toList();
      return;
    }
    final List<ProductModel> matches = <ProductModel>[];
    for (var element in allProductList) {
      if (element.name!.toLowerCase().contains(text.toLowerCase())) {
        matches.add(element);
      }
    }
    productList.value = matches;
    update();
  }

  void toggleSelection(int index, bool value) {
    taxList[index].isSelected = value;
    taxList.refresh();
  }

  List<TaxModel> get selectedTaxes => taxList.where((e) => e.isSelected).toList();
}
