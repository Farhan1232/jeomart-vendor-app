import 'dart:async';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vendor/constant/collection_name.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/models/order_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/models/vendor_model.dart';
import 'package:vendor/service/audio_player_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vendor/utils/fire_store_utils.dart';
import 'package:vendor/utils/firestore_paginator.dart';

class HomeController extends GetxController {
  RxBool isLoading = true.obs;

  Rx<TextEditingController> estimatedTimeController = TextEditingController().obs;
  Rx<TextEditingController> courierCompanyName = TextEditingController().obs;
  Rx<TextEditingController> courierCompanyTrackingId = TextEditingController().obs;

  RxInt selectedTabIndex = 0.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getUserProfile();
    super.onInit();
  }

  RxList<OrderModel> allOrderList = <OrderModel>[].obs;
  RxList<OrderModel> newOrderList = <OrderModel>[].obs;
  RxList<OrderModel> acceptedOrderList = <OrderModel>[].obs;
  RxList<OrderModel> completedOrderList = <OrderModel>[].obs;
  RxList<OrderModel> rejectedOrderList = <OrderModel>[].obs;
  RxList<OrderModel> cancelledOrderList = <OrderModel>[].obs;

  Rx<UserModel> userModel = UserModel().obs;
  Rx<VendorModel> vendermodel = VendorModel().obs;

  /// Loads the Home tab.
  ///
  /// After the profile, the employee role, the store and the first page of
  /// orders used to be fetched one after another, so the tab showed its spinner
  /// for all three round trips. None of them depends on another - each only
  /// needs the profile - so they now run together and the spinner lifts when
  /// the slowest arrives. Each still fills only its own field, and the tab still
  /// waits for all of them.
  Future<void> getUserProfile() async {
    final List<Future<void>> reads = <Future<void>>[];
    await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((value) async {
      if (value != null) {
        userModel.value = value;
        Constant.userModel = userModel.value;
        if (userModel.value.employeePermissionId != null) {
          reads.add(
            FireStoreUtils.getEmployeeRoleById(userModel.value.employeePermissionId!).then((role) {
              Constant.employeeRoleModel = role;
            }),
          );
        }
      }
    });
    if (userModel.value.vendorID != null && userModel.value.vendorID!.isNotEmpty) {
      reads.add(
        FireStoreUtils.getVendorById(userModel.value.vendorID!, allowRecent: true).then((vender) {
          if (vender?.id != null) {
            vendermodel.value = vender!;
          }
        }),
      );
    }
    reads.add(getOrder());
    await Future.wait<void>(reads);

    isLoading.value = false;
  }

  RxList<UserModel> driverUserList = <UserModel>[].obs;
  Rx<UserModel> selectDriverUser = UserModel().obs;

  Future<void> getAllDriverList() async {
    await FireStoreUtils.getAvalibleDrivers().then((value) {
      if (value.isNotEmpty == true) {
        driverUserList.value = value;
      }
    });
    isLoading.value = false;
  }

  /// The store's orders, newest first, loaded a page at a time.
  ///
  /// This used to be an unbounded `snapshots()` listener over the store's
  /// entire order history that also rebuilt all five status lists *inside* the
  /// per-document loop. A store with thousands of orders re-downloaded and
  /// re-processed all of them on every single status change.
  ///
  /// The first page stays live, so a newly placed order still arrives
  /// immediately and still rings; older orders are fetched on scroll.
  FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>? ordersPaginator;

  /// Keeps the derived lists in sync with the loaded pages.
  Worker? _paginatorWorker;

  bool get hasMoreOrders => ordersPaginator?.hasMore.value ?? false;

  /// The order list, kept for the next visit to Home.
  ///
  /// The dashboard builds only the tab on screen, so leaving Home closed this
  /// controller and its list, and coming back built both again: the
  /// whole-screen spinner, page one again, the top-up again - and every page
  /// the vendor had scrolled to was gone. The list now stays open while the
  /// vendor is on another tab (its first page keeps listening, as it did while
  /// Home was open) and the next visit shows it at once. Nothing rings in the
  /// meantime: the ringtone is played by this controller's worker, which still
  /// closes with the controller. Signing out, or another store signing in,
  /// closes the kept list.
  static FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>? _keptOrders;
  static String _keptOrdersVendorId = '';
  static StreamSubscription<User?>? _signOutWatch;

  /// Tab order on the home screen.
  static const List<String> tabKeys = ["new", "accepted", "completed", "rejected", "cancelled"];

  bool _matchesTab(OrderModel order, String tab) {
    switch (tab) {
      case "new":
        return order.status == Constant.orderPlaced;
      case "accepted":
        // "Driver Accepted" is what an order says from the moment a driver
        // takes it until pickup; without it the order left every tab, and its
        // chat with it, for exactly that stretch.
        return order.status == Constant.orderAccepted ||
            order.status == Constant.driverPending ||
            order.status == Constant.driverAccepted ||
            order.status == Constant.driverRejected ||
            order.status == Constant.orderShipped ||
            order.status == Constant.orderInTransit;
      case "completed":
        return order.status == Constant.orderCompleted;
      case "rejected":
        return order.status == Constant.orderRejected;
      case "cancelled":
        return order.status == Constant.orderCancelled;
      default:
        return false;
    }
  }

  Future<void> getOrder() async {
    final String vendorId = Constant.userModel?.vendorID ?? '';
    final FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>? kept = _keptOrders;
    if (ordersPaginator == null && kept != null && canReuseOrders(kept, vendorId)) {
      _showKeptOrders(kept);
      return;
    }
    ordersPaginator?.dispose();
    if (kept != null && !identical(kept, ordersPaginator)) kept.dispose();
    final paginator = FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>(
      source: FirestorePageSource(
        FireStoreUtils.fireStore.collection(CollectionName.vendorOrders).where('vendorID', isEqualTo: Constant.userModel!.vendorID).orderBy('createdAt', descending: true),
        live: true,
      ),
      mapper: (doc) {
        final data = doc.data();
        if (data == null) return null;
        try {
          return OrderModel.fromJson(data);
        } catch (_) {
          return null;
        }
      },
      pageSize: 20,
      autoFillTarget: 10,
      filter: (order) => _matchesTab(order, tabKeys[selectedTabIndex.value]),
    );
    ordersPaginator = paginator;
    _keptOrders = paginator;
    _keptOrdersVendorId = vendorId;
    _watchSignOut();
    _paginatorWorker?.dispose();
    _paginatorWorker = ever<List<OrderModel>>(paginator.items, _splitByStatus);

    // `refresh()` returns only after it has also topped the tab on screen up to
    // ten orders - up to five more pages of 20, fetched one after another,
    // because each page starts where the last one ended. A store whose newest
    // orders are mostly already accepted or completed therefore sat on the
    // whole-screen spinner for six round trips before Home appeared.
    //
    // Home now appears as soon as the first page is in, and the top-up carries
    // on exactly as before. While it does, a tab that has nothing to show yet
    // shows the loader rather than "not found" (see `orderTab`), so the message
    // still only appears once there really is nothing.
    final Future<void> firstPage = _firstPageShown(paginator);
    isFillingOrders.value = true;
    final Future<void> loading = paginator.refresh();
    unawaited(
      loading.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(ordersPaginator, paginator)) isFillingOrders.value = false;
      }),
    );
    await Future.any<void>(<Future<void>>[loading, firstPage]);
  }

  /// True while the first load of orders is still topping up the tab on screen.
  RxBool isFillingOrders = false.obs;

  /// A kept list is shown again only if it is this store's and its first page
  /// arrived without an error; otherwise Home loads a new one, as it always did.
  @visibleForTesting
  static bool canReuseOrders(FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> kept, String vendorId) {
    return vendorId.isNotEmpty && vendorId == _keptOrdersVendorId && !kept.isDisposed && !kept.isInitialLoading.value && kept.error.value == null;
  }

  /// Puts [paginator] where a closed Home tab leaves its list.
  @visibleForTesting
  static void debugKeepOrders(FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>? paginator, String vendorId) {
    _keptOrders = paginator;
    _keptOrdersVendorId = vendorId;
  }

  @visibleForTesting
  static FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>? get debugKeptOrders => _keptOrders;

  /// Shows the kept list: its orders are split into the tabs straight away,
  /// with nothing read. It was topped up when it was first loaded, and its
  /// first page - where new orders arrive - has stayed live since.
  void _showKeptOrders(FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> paginator) {
    ordersPaginator = paginator;
    _paginatorWorker?.dispose();
    _paginatorWorker = ever<List<OrderModel>>(paginator.items, _splitByStatus);
    // The same filter a new list is given, reading this controller's tab.
    paginator.filter = (order) => _matchesTab(order, tabKeys[selectedTabIndex.value]);
    paginator.items.refresh();
  }

  static void _watchSignOut() {
    if (_signOutWatch != null) return;
    try {
      _signOutWatch = FirebaseAuth.instance.authStateChanges().listen((User? user) {
        if (user == null) _dropKeptOrders();
      });
    } catch (e) {
      log('HomeController: no sign-out watch :: $e');
    }
  }

  static void _dropKeptOrders() {
    _keptOrders?.dispose();
    _keptOrders = null;
    _keptOrdersVendorId = '';
  }

  /// Brings one order on the list up to date after the vendor has changed it.
  ///
  /// Reject used to rebuild the whole order list for this: every tab emptied,
  /// the loader came up, page after page was read again, and the pages the
  /// vendor had scrolled to were gone. The first page is live and shows the
  /// change by itself; this re-reads just the one order, so an order further
  /// down the list is brought up to date too.
  Future<void> refreshOrder(String? orderId) async {
    final paginator = ordersPaginator;
    if (paginator == null || orderId == null || orderId.isEmpty) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FireStoreUtils.fireStore.collection(CollectionName.vendorOrders).doc(orderId).get();
      if (doc.exists) paginator.replaceDocument(doc);
    } catch (e) {
      log('HomeController.refreshOrder($orderId) failed :: $e');
    }
  }

  /// Completes once [paginator]'s first page has been split into the tab lists.
  static Future<void> _firstPageShown(FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> paginator) {
    final Completer<void> shown = Completer<void>();
    final Worker worker = ever<bool>(paginator.isInitialLoading, (bool loading) {
      if (!loading && !shown.isCompleted) shown.complete();
    });
    return shown.future.whenComplete(worker.dispose);
  }

  /// Called when the home screen's tab changes.
  Future<void> onTabChanged(int index) async {
    selectedTabIndex.value = index;
    await ordersPaginator?.applyFilter((order) => _matchesTab(order, tabKeys[index]));
  }

  /// True while more orders are being fetched for the tab on screen - the
  /// spinner at the end of the list.
  RxBool isLoadingMoreOrders = false.obs;

  /// How many more orders of the tab on screen one scroll to the end asks for.
  static const int moreOrdersPerScroll = 10;

  /// Loads older orders when the vendor scrolls to the end of a tab.
  ///
  /// It used to read one page of the store's orders, whatever their status. A
  /// page could hold nothing for the tab on screen, so nothing arrived and the
  /// spinner row stayed. It now reads on until the tab has more to show,
  /// bounded like the first load's top-up.
  Future<void> loadMoreOrders() async {
    final paginator = ordersPaginator;
    if (paginator == null || isLoadingMoreOrders.value || !paginator.hasMore.value) return;
    isLoadingMoreOrders.value = true;
    try {
      await paginator.loadMoreVisible(atLeast: moreOrdersPerScroll);
    } finally {
      isLoadingMoreOrders.value = false;
    }
  }

  Future<void> refreshOrders() async {
    await ordersPaginator?.refresh();
  }

  /// Splits the loaded orders into the five tab lists once per update, instead
  /// of once per document.
  Future<void> _splitByStatus(List<OrderModel> orders) async {
    allOrderList.value = orders;
    newOrderList.value = orders.where((p0) => _matchesTab(p0, "new")).toList();
    acceptedOrderList.value = orders.where((p0) => _matchesTab(p0, "accepted")).toList();
    completedOrderList.value = orders.where((p0) => _matchesTab(p0, "completed")).toList();
    rejectedOrderList.value = orders.where((p0) => _matchesTab(p0, "rejected")).toList();
    cancelledOrderList.value = orders.where((p0) => _matchesTab(p0, "cancelled")).toList();
    update();
    await AudioPlayerService.playSound(newOrderList.isNotEmpty);
  }

  @override
  void onClose() {
    _paginatorWorker?.dispose();
    _paginatorWorker = null;
    // The list is kept for the next visit to Home (see `_keptOrders`); any
    // other list is closed, as before.
    if (!identical(ordersPaginator, _keptOrders)) ordersPaginator?.dispose();
    ordersPaginator = null;
    super.onClose();
  }
}
