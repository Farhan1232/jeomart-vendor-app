import 'package:get/get.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/models/product_model.dart';
import 'package:vendor/models/tax_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/models/vendor_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vendor/utils/fire_store_utils.dart';
import 'package:vendor/utils/firestore_paginator.dart';

class ProductListController extends GetxController {
  @override
  void onInit() {
    // TODO: implement onInit
    getUserProfile();
    super.onInit();
  }

  Rx<UserModel> userModel = UserModel().obs;
  Rx<VendorModel> vendorModel = VendorModel().obs;
  RxBool isLoading = true.obs;
  RxList<TaxModel> taxList = <TaxModel>[].obs;

  Future<void> getUserProfile() async {
    taxList.value = Constant.taxProductList ?? [];

    await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((value) {
      if (value != null) {
        Constant.userModel = value;
        userModel.value = value;
      }
    });
    await getProduct();
    isLoading.value = false;
  }

  /// The catalogue is paged instead of downloading every product the store has.
  FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, ProductModel>? productsPaginator;

  /// Keeps the derived lists in sync with the loaded pages.
  Worker? _paginatorWorker;

  RxList<ProductModel> productList = <ProductModel>[].obs;

  bool get hasMoreProducts => productsPaginator?.hasMore.value ?? false;

  /// How many products the store has in total, or -1 while unknown.
  ///
  /// The plan's product limit is checked against this. Since the catalogue
  /// became paginated, `productList` only holds the pages loaded so far (20 at
  /// first), so a store over its limit could keep adding products - before
  /// pagination the check counted the whole catalogue. This is a Firestore
  /// `count()` over the very same query, so it is that same number again,
  /// without downloading the catalogue.
  RxInt totalProductCount = (-1).obs;

  /// The count the product-limit check compares with the plan's limit.
  int get productCountForLimit => totalProductCount.value > productList.length ? totalProductCount.value : productList.length;

  Future<void> _loadProductCount() async {
    try {
      final AggregateQuerySnapshot snapshot = await FireStoreUtils.productsQuery().count().get();
      totalProductCount.value = snapshot.count ?? -1;
    } catch (_) {
      // Unknown: the check falls back to the loaded rows, as it did before.
      totalProductCount.value = -1;
    }
  }

  Future<void> getProduct() async {
    // The store document, the first page of products and the product count are
    // independent reads; the store used to be fetched before the list started.
    final List<Future<void>> reads = <Future<void>>[_loadProductCount()];
    if (userModel.value.vendorID != null) {
      reads.add(
        FireStoreUtils.getVendorById(userModel.value.vendorID ?? '', allowRecent: true).then((value) {
          if (value != null) {
            vendorModel.value = value;
          }
        }),
      );
    }
    productsPaginator?.dispose();
    final paginator = FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, ProductModel>(
      source: FirestorePageSource(FireStoreUtils.productsQuery()),
      mapper: (doc) {
        final data = doc.data();
        if (data == null) return null;
        try {
          return ProductModel.fromJson(data);
        } catch (_) {
          return null;
        }
      },
      pageSize: 20,
    );
    productsPaginator = paginator;
    _paginatorWorker?.dispose();
    _paginatorWorker = ever<List<ProductModel>>(paginator.items, (items) {
      productList.value = items;
    });
    reads.add(paginator.refresh());
    await Future.wait<void>(reads);
  }

  Future<void> loadMoreProducts() async {
    await productsPaginator?.loadMore();
  }

  Future<void> refreshProducts() async {
    await productsPaginator?.refresh();
  }

  @override
  void onClose() {
    _paginatorWorker?.dispose();
    _paginatorWorker = null;
    productsPaginator?.dispose();
    productsPaginator = null;
    super.onClose();
  }

  Future<void> updateList(int index, bool isPublish) async {
    ProductModel productModel = productList[index];
    if (isPublish == true) {
      productModel.publish = false;
    } else {
      productModel.publish = true;
    }

    productList.removeAt(index);
    productList.insert(index, productModel);
    update();
    await FireStoreUtils.setProduct(productModel);
  }

  void toggleSelection(int index, bool value) {
    taxList[index].isSelected = value;
    taxList.refresh();
  }

  List<TaxModel> get selectedTaxes => taxList.where((e) => e.isSelected).toList();
  List<ProductModel> get selectedProducts => productList.where((p) => selectedProductIds.contains(p.id)).toList();

  RxSet<String> selectedProductIds = <String>{}.obs;

  void toggleProductSelection(ProductModel product) {
    if (selectedProductIds.contains(product.id)) {
      selectedProductIds.remove(product.id);
    } else {
      selectedProductIds.add(product.id.toString());
    }
  }

  void clearSelection() {
    selectedProductIds.clear();
  }

  String getTaxDisplayText(List<TaxModel>? taxes) {
    if (taxes == null || taxes.isEmpty) return '';

    return taxes
        .map((tax) {
          if (tax.type == "fix") {
            return "${tax.title} (${Constant.amountShow(amount: tax.tax)})";
          } else {
            return "${tax.title} (${tax.tax}%)";
          }
        })
        .join(', ');
  }
}
