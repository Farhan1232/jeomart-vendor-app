import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vendor/app/Home_screen/home_screen.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/controller/home_controller.dart';
import 'package:vendor/models/order_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/utils/firestore_paginator.dart';

/// Session 52 - "the vendor app has no pagination": it had, but the order list
/// was thrown away and rebuilt on every visit to Home and after every Reject, a
/// scroll to the end of a tab could bring nothing for that tab, and the spinner
/// row at the end of every tab spun whether or not anything was loading.
class Doc {
  Doc(this.id, this.status);

  final String id;
  final String status;
}

/// What Firestore's query documents are to a plain document: a narrower type.
class QueryDoc extends Doc {
  QueryDoc(super.id, super.status);
}

class Source extends PageSource<Doc> {
  Source(this.docs);

  final List<Doc> docs;
  int fetches = 0;

  @override
  Future<List<Doc>> fetch({required Doc? after, required int limit}) async {
    fetches++;
    var start = 0;
    if (after != null) start = docs.indexWhere((Doc d) => d.id == after.id) + 1;
    // A list of the narrower type, as `QuerySnapshot.docs` is.
    return docs.skip(start).take(limit).map((Doc d) => QueryDoc(d.id, d.status)).toList();
  }

  @override
  String idOf(Doc doc) => doc.id;
}

/// One rejected order in every [every] orders, the rest completed.
List<Doc> history(int count, {int every = 30}) => List<Doc>.generate(count, (int i) => Doc('o$i', i % every == every - 1 ? 'Order Rejected' : 'Order Completed'));

FirestorePaginator<Doc, Doc> paginatorOver(Source source, {bool Function(Doc)? filter}) =>
    FirestorePaginator<Doc, Doc>(source: source, mapper: (Doc d) => d, pageSize: 20, filter: filter);

// A stand-in for Firestore's document, which is sealed.
// ignore: subtype_of_sealed_class
class FakeSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  FakeSnapshot(this.id, this._data);

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  bool get exists => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OrderSource extends PageSource<DocumentSnapshot<Map<String, dynamic>>> {
  OrderSource(this.docs);

  final List<FakeSnapshot> docs;
  int fetches = 0;

  @override
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> fetch({required DocumentSnapshot<Map<String, dynamic>>? after, required int limit}) async {
    fetches++;
    var start = 0;
    if (after != null) start = docs.indexWhere((FakeSnapshot d) => d.id == after.id) + 1;
    return docs.skip(start).take(limit).toList();
  }

  @override
  String idOf(DocumentSnapshot<Map<String, dynamic>> doc) => doc.id;
}

FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> orderPaginator(List<String> statuses, {OrderSource? source}) {
  final List<FakeSnapshot> docs = <FakeSnapshot>[
    for (int i = 0; i < statuses.length; i++) FakeSnapshot('o$i', <String, dynamic>{'id': 'o$i', 'status': statuses[i], 'vendorID': 'v1'}),
  ];
  return FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel>(
    source: source ?? OrderSource(docs),
    mapper: (DocumentSnapshot<Map<String, dynamic>> doc) => OrderModel.fromJson(doc.data()!),
    pageSize: 20,
    // As Home's own list: topped up to ten orders of the tab on screen.
    autoFillTarget: 10,
    filter: (OrderModel o) => o.status == 'Order Placed',
  );
}

class ListHomeController extends HomeController {
  int refreshed = 0;
  int loadMore = 0;

  @override
  Future<void> getUserProfile() async {}

  @override
  Future<void> refreshOrders() async => refreshed++;

  @override
  Future<void> loadMoreOrders() async => loadMore++;
}

class OrdersHomeController extends HomeController {
  @override
  Future<void> getUserProfile() async {}
}

void main() {
  group('scrolling to the end of a tab', () {
    test('one page could bring nothing for the tab on screen', () async {
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(Source(history(200)), filter: (Doc d) => d.status == 'Order Rejected');
      await paginator.refresh();
      final int before = paginator.visibleItems.length;
      await paginator.loadMore();
      // Page two (o20-o39) holds o29; page three would hold nothing new for a while.
      expect(paginator.visibleItems.length - before, lessThanOrEqualTo(1));
    });

    test('now it reads on until the tab has more to show', () async {
      final Source source = Source(history(400));
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(source, filter: (Doc d) => d.status == 'Order Rejected');
      await paginator.refresh();
      final int before = paginator.visibleItems.length;
      await paginator.loadMoreVisible(atLeast: 2);
      expect(paginator.visibleItems.length, greaterThanOrEqualTo(before + 2));
    });

    test('bounded: a tab with nothing further down stops after the page limit', () async {
      final Source source = Source(List<Doc>.generate(1000, (int i) => Doc('o$i', 'Order Completed')));
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(source, filter: (Doc d) => d.status == 'Order Rejected');
      await paginator.refresh();
      final int fetches = source.fetches;
      await paginator.loadMoreVisible(atLeast: 10, maxPages: 5);
      expect(source.fetches - fetches, 5);
    });

    test('stops at the end of the history', () async {
      final Source source = Source(history(45));
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(source, filter: (Doc d) => d.status == 'Order Rejected');
      await paginator.refresh();
      await paginator.loadMoreVisible(atLeast: 50);
      expect(paginator.hasMore.value, isFalse);
      expect(paginator.items.length, 45);
    });

    test('a closed list reads nothing', () async {
      final Source source = Source(history(100));
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(source);
      await paginator.refresh();
      paginator.dispose();
      final int fetches = source.fetches;
      await paginator.loadMoreVisible(atLeast: 10);
      expect(source.fetches, fetches);
    });
  });

  group('one order brought up to date', () {
    test('an order on a later page gets its new status, nothing is reloaded', () async {
      final Source source = Source(history(60));
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(source);
      await paginator.refresh();
      await paginator.loadMore();
      await paginator.loadMore();
      final int fetches = source.fetches;
      expect(paginator.items.length, 60);

      paginator.replaceDocument(Doc('o45', 'Order Rejected'));

      expect(paginator.items.firstWhere((Doc d) => d.id == 'o45').status, 'Order Rejected');
      expect(paginator.items.length, 60);
      expect(paginator.items.map((Doc d) => d.id).toList(), List<String>.generate(60, (int i) => 'o$i'));
      expect(source.fetches, fetches);
    });

    test('a page of the narrower document type takes a plain document', () async {
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(Source(history(20)));
      await paginator.refresh();
      expect(() => paginator.replaceDocument(Doc('o3', 'Order Rejected')), returnsNormally);
      expect(paginator.items[3].status, 'Order Rejected');
    });

    test('paging carries on from the same place afterwards', () async {
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(Source(history(60)));
      await paginator.refresh();
      paginator.replaceDocument(Doc('o19', 'Order Rejected'));
      await paginator.loadMore();
      expect(paginator.items.map((Doc d) => d.id).toList(), List<String>.generate(40, (int i) => 'o$i'));
    });

    test('an order that is not on the list is ignored', () async {
      final FirestorePaginator<Doc, Doc> paginator = paginatorOver(Source(history(20)));
      await paginator.refresh();
      final List<Doc> before = List<Doc>.of(paginator.items);
      paginator.replaceDocument(Doc('elsewhere', 'Order Rejected'));
      expect(paginator.items, before);
    });
  });

  group('the order list is kept between visits to Home', () {
    setUp(() {
      Constant.userModel = UserModel(id: 'u1', vendorID: 'v1');
    });

    tearDown(() {
      HomeController.debugKeepOrders(null, '');
      Get.reset();
    });

    test('only for the same store, and only a list that loaded', () async {
      final FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> kept = orderPaginator(<String>['Order Placed']);
      HomeController.debugKeepOrders(kept, 'v1');
      expect(HomeController.canReuseOrders(kept, 'v1'), isFalse, reason: 'its first page has not arrived yet');

      await kept.refresh();
      expect(HomeController.canReuseOrders(kept, 'v1'), isTrue);
      expect(HomeController.canReuseOrders(kept, 'v2'), isFalse, reason: 'another store never sees these orders');
      expect(HomeController.canReuseOrders(kept, ''), isFalse);

      kept.error.value = StateError('page failed');
      expect(HomeController.canReuseOrders(kept, 'v1'), isFalse);
      kept.error.value = null;

      kept.dispose();
      expect(HomeController.canReuseOrders(kept, 'v1'), isFalse);
    });

    test('coming back to Home shows the kept orders at once, split into the tabs, reading nothing', () async {
      final List<String> statuses = <String>['Order Placed', 'Driver Accepted', 'Order Completed', 'Order Rejected'];
      final OrderSource source = OrderSource(<FakeSnapshot>[
        for (int i = 0; i < statuses.length; i++) FakeSnapshot('o$i', <String, dynamic>{'id': 'o$i', 'status': statuses[i], 'vendorID': 'v1'}),
      ]);
      final FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> kept = orderPaginator(statuses, source: source);
      await kept.refresh();
      HomeController.debugKeepOrders(kept, 'v1');
      final int fetches = source.fetches;

      final OrdersHomeController controller = OrdersHomeController();
      await controller.getOrder();
      await Future<void>.delayed(Duration.zero);

      expect(identical(controller.ordersPaginator, kept), isTrue, reason: 'nothing was read again');
      expect(controller.newOrderList.map((OrderModel o) => o.id), <String>['o0']);
      expect(controller.acceptedOrderList.map((OrderModel o) => o.id), <String>['o1']);
      expect(controller.completedOrderList.map((OrderModel o) => o.id), <String>['o2']);
      expect(controller.rejectedOrderList.map((OrderModel o) => o.id), <String>['o3']);
      expect(controller.isFillingOrders.value, isFalse);
      expect(source.fetches, fetches, reason: 'the New tab has fewer than ten orders, and still nothing is read again');
      expect(controller.ordersPaginator!.visibleItems.map((OrderModel o) => o.id), <String>['o0'], reason: "the filter follows this controller's tab");
    });

    test('leaving Home keeps the list open; a list that is not kept is closed as before', () async {
      final FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> kept = orderPaginator(<String>['Order Placed']);
      await kept.refresh();
      HomeController.debugKeepOrders(kept, 'v1');

      final OrdersHomeController home = OrdersHomeController();
      await home.getOrder();
      home.onClose();
      expect(kept.isDisposed, isFalse);
      expect(HomeController.debugKeptOrders, same(kept));

      final FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> other = orderPaginator(<String>['Order Placed']);
      final OrdersHomeController second = OrdersHomeController()..ordersPaginator = other;
      second.onClose();
      expect(other.isDisposed, isTrue);
    });
  });

  group('loading more from Home', () {
    test('keeps reading until the tab on screen has more, and says so while it does', () async {
      final List<String> statuses = List<String>.generate(200, (int i) => i % 25 == 24 ? 'Order Rejected' : 'Order Completed');
      final FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, OrderModel> paginator = orderPaginator(statuses);
      paginator.filter = (OrderModel o) => o.status == 'Order Rejected';
      await paginator.refresh();

      final OrdersHomeController controller = OrdersHomeController()..ordersPaginator = paginator;
      final List<bool> spinner = <bool>[];
      final Worker worker = ever<bool>(controller.isLoadingMoreOrders, spinner.add);
      final int before = paginator.visibleItems.length;
      await controller.loadMoreOrders();
      worker.dispose();

      expect(paginator.visibleItems.length, greaterThan(before));
      expect(spinner, <bool>[true, false]);
    });
  });

  group('a short order tab', () {
    Widget tab(HomeController controller, int count) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: const HomeScreen().orderTab(
            controller,
            false,
            orders: List<OrderModel>.generate(count, (int i) => OrderModel(id: 'o$i')).obs,
            emptyMessage: 'Nothing here',
            card: (BuildContext _, OrderModel order) => SizedBox(height: 120, child: Text(order.id!)),
          ),
        ),
      ),
    );

    testWidgets('can still be pulled to refresh and scrolled to load more', (WidgetTester tester) async {
      final ListHomeController controller = ListHomeController();
      await tester.pumpWidget(tab(controller, 1));

      await tester.fling(find.text('o0'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(controller.refreshed, 1);

      await tester.drag(find.text('o0'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(controller.loadMore, greaterThan(0));
    });

    testWidgets('shows the spinner row only while more orders are being fetched', (WidgetTester tester) async {
      final ListHomeController controller = ListHomeController();
      await tester.pumpWidget(tab(controller, 2));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      controller.isLoadingMoreOrders.value = true;
      await tester.pumpWidget(tab(controller, 2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('this change, and only this change', () {
    String code(String path) => File(path).readAsStringSync().split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

    final String home = code('lib/app/Home_screen/home_screen.dart');
    final String controller = code('lib/controller/home_controller.dart');

    test('Reject brings just its order up to date', () {
      final int reject = home.indexOf('orderModel.status = Constant.orderRejected;');
      final String branch = home.substring(reject, home.indexOf('Get.back();', reject));
      expect(branch, contains('controller.refreshOrder(orderModel.id);'));
      expect(branch, isNot(contains('getOrder()')));
    });

    test("Reject's writes are exactly as they were, one after another", () {
      final int reject = home.indexOf('orderModel.status = Constant.orderRejected;');
      final String branch = home.substring(reject, home.indexOf('ShowToastDialog.closeLoader();', reject));
      expect(branch, contains('await FireStoreUtils.deleteCashbackRedeem(orderModel);'));
      expect(branch, contains('await FireStoreUtils.updateOrder(orderModel);'));
      expect(branch, contains('await FireStoreUtils.fireStore.collection(CollectionName.wallet).doc(historyModel.id).set(historyModel.toJson());'));
      expect(branch, contains('await FireStoreUtils.updateUserWallet(amount: finalAmount.toString(), userId: orderModel.author!.id.toString());'));
      expect(branch, isNot(contains('Future.wait')));
    });

    test('Cancel and Mark Deliver still reload the list as before (not part of this request)', () {
      expect('controller.getOrder()'.allMatches(home).length, 2);
    });

    test('every Accept sends its writes together, and still sends all of them', () {
      final String flat = home.replaceAll(RegExp(r'\s+'), ' ');
      const String orderAndEarnings = 'await Future.wait(<Future<void>>[ FireStoreUtils.updateOrder(orderModel), FireStoreUtils.restaurantVendorWalletSet(orderModel), ]);';
      const String withDeliveryMan =
          'await Future.wait(<Future<void>>[ FireStoreUtils.updateOrder(orderModel), FireStoreUtils.updateDriverUser(controller.selectDriverUser.value), FireStoreUtils.restaurantVendorWalletSet(orderModel), ]);';
      // The Accept button (session 49), the Self Delivery button's accept, the
      // estimated-time dialog and the courier dialog.
      expect(orderAndEarnings.allMatches(flat).length, 4);
      expect(withDeliveryMan.allMatches(flat).length, 1);
      // Left as it was: the takeaway "Delivered" button, which is not an accept.
      expect('await FireStoreUtils.updateOrder(orderModel); await FireStoreUtils.restaurantVendorWalletSet'.allMatches(flat).length, 1);
      expect(flat.contains('await FireStoreUtils.updateOrder(orderModel); await FireStoreUtils.restaurantVendorWalletSet(orderModel); SendNotification.sendFcmMessage(Constant.takeawayCompleted'), isTrue);
      expect(flat.contains('await FireStoreUtils.updateOrder(orderModel); await FireStoreUtils.updateDriverUser'), isFalse);
    });

    test('signing out closes the kept list', () {
      expect(controller, contains('FirebaseAuth.instance.authStateChanges().listen((User? user) {\n        if (user == null) _dropKeptOrders();'));
    });

    test('pull to refresh still reloads everything', () {
      expect(controller, contains('await ordersPaginator?.refresh();'));
    });
  });
}
