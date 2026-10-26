import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vendor/app/Home_screen/home_screen.dart';
import 'package:vendor/constant/show_toast_dialog.dart';
import 'package:vendor/controller/home_controller.dart';
import 'package:vendor/models/order_model.dart';
import 'package:vendor/widget/tab_selection_listener.dart';

/// Source with comments removed, so an assertion can never be satisfied by the
/// explanatory comments that quote the old code (the Session 19/26 trap).
String code(String path) {
  final String source = File(path).readAsStringSync();
  return source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAllMapped(RegExp(r'(^|\s)//.*$', multiLine: true), (Match m) => m[1]!);
}

/// The text of the method starting at [signature], up to the next member.
String method(String source, String signature) {
  final int start = source.indexOf(signature);
  expect(start, isNot(-1), reason: 'missing: $signature');
  final int end = source.indexOf(RegExp(r'\n  (Future<|static |void |bool |Widget |InkWell |Dialog |@override)'), start + signature.length);
  return source.substring(start, end == -1 ? source.length : end);
}

class _FakeHomeController extends HomeController {
  int refreshed = 0;
  int loadMore = 0;

  @override
  Future<void> refreshOrders() async => refreshed++;

  @override
  Future<void> loadMoreOrders() async => loadMore++;
}

void main() {
  group('startup', () {
    test('the splash screen no longer sleeps three seconds before starting', () {
      final String splash = code('lib/controller/splash_controller.dart');
      expect(splash.contains('Timer('), isFalse);
      expect(splash.contains('Duration(seconds: 3)'), isFalse);
      expect(splash.contains('GlobalSettingController.settingsReady'), isTrue);
    });

    test('every splash exit is guarded: a throw retries, and no chosen screen lands on login', () {
      final String splash = code('lib/controller/splash_controller.dart');
      expect(splash.contains('catch (e, s)'), isTrue);
      expect(splash.contains('if (!_navigated)'), isTrue);
      // Every navigation goes through _go, which is what `_navigated` records.
      expect(RegExp(r'Get\.offAll\(').allMatches(splash).length, 1);
    });

    test('the token save cannot hold the splash screen open without a connection', () {
      final String splash = code('lib/controller/splash_controller.dart');
      expect(splash.contains('await save().timeout('), isTrue);
    });

    test('the splash wait is released even if the settings fail', () {
      final String settings = code('lib/controller/global_setting_controller.dart');
      expect(RegExp(r'finally\s*\{\s*if \(!_settingsReady\.isCompleted\) _settingsReady\.complete\(\);').hasMatch(settings), isTrue);
    });

    test('getSettings waits for all 17 settings documents and fires none off unobserved', () {
      final String body = method(code('lib/utils/fire_store_utils.dart'), 'static Future<void> getSettings()');
      expect(RegExp(r'\bread\("').allMatches(body).length, 14);
      expect(RegExp(r'\blisten\("').allMatches(body).length, 3);
      expect(body.contains('await Future.wait<void>(firstPass)'), isTrue);
      // No bare `fireStore...get().then(` / `.snapshots().listen((event)` left outside the guards.
      expect(RegExp(r'\n      fireStore\.collection').hasMatch(body), isFalse);
    });

    test('a geocoder failure no longer leaves the whole app on the dashboard spinner', () {
      final String dashboard = code('lib/controller/dash_board_controller.dart');
      final String taxRead = method(dashboard, 'Future<List<TaxModel>?> _readTaxList()');
      expect(taxRead.contains('try {'), isTrue);
      expect(taxRead.contains('catch (e)'), isTrue);
      expect(dashboard.contains('FireStoreUtils.getTaxList('), isTrue);
      expect(RegExp(r'getTaxList\(').allMatches(dashboard).length, 1, reason: 'the only tax read is the guarded one');
    });

    test("the dashboard still applies the user's own section last", () {
      final String getVendor = method(code('lib/controller/dash_board_controller.dart'), 'Future<void> getVendor()');
      final int vendorSection = getVendor.indexOf('await vendorSectionRead!.then');
      final int taxes = getVendor.indexOf('await taxRead.then');
      final int userSection = getVendor.indexOf('await userSectionRead.then');
      expect(vendorSection, isNot(-1));
      expect(taxes, greaterThan(vendorSection));
      expect(userSection, greaterThan(taxes));
      expect(getVendor.indexOf('setPage();'), greaterThan(userSection));
    });
  });

  group('reads that may reuse a recent store document', () {
    test('only the dashboard and the Home, Products and Dine-in tabs opt in', () {
      final Set<String> optedIn = <String>{};
      for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (code(entity.path).contains('allowRecent: true')) optedIn.add(entity.path.replaceAll('\\', '/'));
      }
      expect(optedIn, <String>{
        'lib/controller/dash_board_controller.dart',
        'lib/controller/home_controller.dart',
        'lib/controller/product_list_controller.dart',
        'lib/controller/dine_in_order_controller.dart',
      });
    });

    test('a store write drops the recent copy before writing', () {
      final String update = method(code('lib/utils/fire_store_utils.dart'), 'static Future<VendorModel?> updateVendor(');
      expect(update.indexOf('RecentDocCache.invalidate('), lessThan(update.indexOf('.set(vendor.toJson())')));
    });
  });

  group('wallet', () {
    test('the wallet only reuses the cached profile when it is the signed-in vendor', () {
      final String wallet = code('lib/controller/wallet_controller.dart');
      expect(wallet.contains('cachedUser != null && cachedUser.id == FireStoreUtils.getCurrentUid()'), isTrue);
    });

    test('withdrawals and the withdraw method wait for that check; the history does not', () {
      final String load = method(code('lib/controller/wallet_controller.dart'), 'Future<void> getWalletTransaction(');
      final int user = load.indexOf('_loadUser().then');
      expect(user, isNot(-1));
      expect(load.indexOf('_loadWithdrawals()'), greaterThan(user));
      expect(load.indexOf('getPaymentMethod()'), greaterThan(user));
      expect(load.indexOf('_loadTransactions(isFilter)'), lessThan(user));
      expect(load.indexOf('isLoading.value = false'), greaterThan(load.indexOf('getPaymentMethod()')));
    });
  });

  group('home tab', () {
    test('a swipe between order tabs reaches the paginator', () {
      final String home = code('lib/app/Home_screen/home_screen.dart');
      expect(home.contains('TabSelectionListener('), isTrue);
      expect(home.contains('onChanged: controller.onTabChanged'), isTrue);
    });

    test('the Home tab starts the role, store and orders reads together', () {
      final String load = method(code('lib/controller/home_controller.dart'), 'Future<void> getUserProfile()');
      expect(load.contains('await Future.wait<void>(reads)'), isTrue);
      expect(load.indexOf('await Future.wait<void>(reads)'), lessThan(load.indexOf('isLoading.value = false')));
    });

    testWidgets('an empty order tab can be pulled to refresh and asks for more', (WidgetTester tester) async {
      final _FakeHomeController controller = _FakeHomeController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: const HomeScreen().orderTab(controller, false, orders: <OrderModel>[].obs, emptyMessage: 'Nothing here', card: (_, _) => const SizedBox()),
            ),
          ),
        ),
      );
      expect(find.text('Nothing here'), findsOneWidget);

      await tester.fling(find.text('Nothing here'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();

      expect(controller.refreshed, 1, reason: 'the empty state used to be an unscrollable Center');
      expect(controller.loadMore, greaterThan(0));
    });

    testWidgets('an order tab builds each card with its list item context and is not shrink-wrapped', (WidgetTester tester) async {
      final _FakeHomeController controller = _FakeHomeController();
      final List<String> built = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: const HomeScreen().orderTab(
                controller,
                false,
                orders: <OrderModel>[OrderModel(id: 'o1'), OrderModel(id: 'o2')].obs,
                emptyMessage: 'Nothing here',
                card: (BuildContext itemContext, OrderModel order) {
                  built.add(order.id!);
                  return SizedBox(height: 50, child: Text(order.id!));
                },
              ),
            ),
          ),
        ),
      );
      expect(built, <String>['o1', 'o2']);
      expect(tester.widget<ListView>(find.byType(ListView)).shrinkWrap, isFalse);
      expect(find.text('Nothing here'), findsNothing);
    });
  });

  group('TabSelectionListener', () {
    testWidgets('a swipe reports the new tab once, as a tap does', (WidgetTester tester) async {
      final List<int> reported = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                bottom: const TabBar(
                  tabs: <Widget>[
                    Tab(text: 'A'),
                    Tab(text: 'B'),
                    Tab(text: 'C'),
                  ],
                ),
              ),
              body: TabSelectionListener(
                onChanged: reported.add,
                child: const TabBarView(
                  children: <Widget>[
                    Center(child: Text('page A')),
                    Center(child: Text('page B')),
                    Center(child: Text('page C')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.fling(find.text('page A'), const Offset(-500, 0), 2000);
      await tester.pumpAndSettle();
      expect(reported, <int>[1]);

      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      expect(reported, <int>[1, 2]);
    });
  });

  group('loader watchdog', () {
    testWidgets('a loader nobody closes comes down after 30 s; an upload loader is allowed 10 min', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(builder: EasyLoading.init(), home: const SizedBox()));

      ShowToastDialog.showLoader('Please wait');
      await tester.pump();
      expect(ShowToastDialog.hasPendingLoader, isTrue);
      await tester.pump(const Duration(seconds: 31));
      expect(ShowToastDialog.hasPendingLoader, isFalse);
      await tester.pumpAndSettle();

      ShowToastDialog.showLoader('Uploading video...', longRunning: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      expect(ShowToastDialog.hasPendingLoader, isTrue, reason: 'an upload must not be un-blocked mid-way');
      ShowToastDialog.closeLoader();
      expect(ShowToastDialog.hasPendingLoader, isFalse);
      await tester.pumpAndSettle();
    });

    test('every loader shown over an upload or a payment uses the long backstop', () {
      final Map<String, int> longLoaders = <String, int>{
        'lib/controller/add_product_controller.dart': 1,
        'lib/app/product_screens/add_product_screen.dart': 2,
        'lib/controller/add_restaurant_controller.dart': 1,
        'lib/controller/dine_in_create_controller.dart': 1,
        'lib/controller/add_edit_coupon_controller.dart': 1,
        'lib/controller/add_advertisement_controller.dart': 1,
        'lib/controller/edit_profile_controller.dart': 1,
        'lib/app/verification_screen/verification_details_upload_screen.dart': 1,
        'lib/app/add_story_screen/add_story_screen.dart': 3,
        'lib/controller/subscription_controller.dart': 8,
        'lib/utils/fire_store_utils.dart': 3,
      };
      longLoaders.forEach((String path, int expected) {
        expect(RegExp(r'showLoader\([^;]*longRunning: true\)').allMatches(code(path)).length, expected, reason: path);
      });
    });
  });

  group('other defects fixed on the way', () {
    test('every network image goes through the app image cache', () {
      for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String source = code(entity.path);
        final int images = RegExp(r'CachedNetworkImage\(').allMatches(source).length;
        final int cached = RegExp(r'CachedNetworkImage\((\s*[^)]*?)?cacheManager: AppImageCache\.manager').allMatches(source).length;
        expect(cached, images, reason: entity.path);
      }
    });

    test('the pagination widget no longer disposes a ScrollController it was handed', () {
      final String pagination = code('lib/widget/firebase_pagination/src/firestore_pagination.dart');
      expect(pagination.contains('if (widget.controller == null) _controller.dispose();'), isTrue);
      expect(RegExp(r'\.\.dispose\(\)').hasMatch(pagination), isFalse);
    });

    test('notifications reuse the FCM access token instead of minting one per message', () {
      final String send = code('lib/constant/send_notification.dart');
      expect(send.contains('_credentials'), isTrue);
      expect(send.contains('client.close()'), isTrue);
      expect(send.contains('accessToken.expiry'), isTrue);
    });

    test("the plan's product limit counts the whole catalogue again, not just the loaded page", () {
      final String screen = code('lib/app/product_screens/product_list_screen.dart');
      expect(RegExp(r'<=\s*controller\.productCountForLimit\)').allMatches(screen).length, 2);
      expect(RegExp(r'<=\s*controller\.productList\.length\)').hasMatch(screen), isFalse);
    });

    test('editing a coupon without an image no longer spins for ever', () {
      expect(code('lib/controller/add_edit_coupon_controller.dart').contains('image != null ||'), isFalse);
    });

    test('an empty advert pause note shows a toast, not a loader that never closes', () {
      final String adverts = code('lib/controller/advertisement_list_controller.dart');
      expect(adverts.contains('showLoader("Please enter pause note"'), isFalse);
      expect(adverts.contains('showToast("Please enter pause note"'), isTrue);
    });
  });
}
