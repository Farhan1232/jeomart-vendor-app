import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vendor/app/Home_screen/home_screen.dart';
import 'package:vendor/controller/admin_product_controller.dart';
import 'package:vendor/controller/home_controller.dart';
import 'package:vendor/models/order_model.dart';
import 'package:vendor/models/product_model.dart';
import 'package:vendor/utils/box_sized_image.dart';
import 'package:vendor/widget/animated_border_container.dart';

/// Source with comments removed, so an assertion can never be satisfied by the
/// explanatory comments that quote the old code.
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

/// A 40 x 30 PNG.
final List<int> _png40x30 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAALElEQVR4nO3NMQEAAAQAMATRP4pYKvg8W4HldMeHelnFYrFYLBaLxWKxWHyyHdwBQE1gaCAAAAAASUVORK5CYII=',
);

Future<ImageInfo> _resolve(WidgetTester tester, ImageProvider provider) async {
  return (await tester.runAsync(() {
    final Completer<ImageInfo> done = Completer<ImageInfo>();
    provider.resolve(ImageConfiguration.empty).addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        if (!done.isCompleted) done.complete(info);
      }, onError: (Object e, StackTrace? s) {
        if (!done.isCompleted) done.completeError(e, s);
      }),
    );
    return done.future;
  }))!;
}

class _FillingHomeController extends HomeController {
  // Deliberately skips HomeController.onInit, which starts the Firestore reads.
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  group('picked-photo previews', () {
    test('the decode size keeps the photo shape and covers the box on both sides', () {
      void check(int w, int h, int bw, int bh, int? ew, int? eh) {
        final size = BoxSizedImage.targetSize(w, h, bw, bh);
        expect(<int?>[size.width, size.height], <int?>[ew, eh], reason: '$w x $h into $bw x $bh');
        if (ew != null) {
          expect(ew, greaterThanOrEqualTo(bw));
          expect(eh, greaterThanOrEqualTo(bh));
        }
      }

      check(4000, 3000, 240, 240, 320, 240); // landscape camera photo, 80 pt at 3x
      check(3000, 4000, 240, 240, 240, 320); // portrait
      check(8000, 1000, 240, 240, 1920, 240); // panorama: still covers the height
      check(4000, 3000, 972, 486, 972, 729); // wide box (verification document)
      check(100, 100, 240, 240, null, null); // already small: decoded as it is
      check(0, 0, 240, 240, null, null);
    });

    testWidgets('a real image is decoded at the covering size, not at full size', (WidgetTester tester) async {
      imageCache.clear();
      final ImageInfo small = await _resolve(tester, BoxSizedImage(MemoryImage(Uint8List.fromList(_png40x30)), width: 10, height: 10));
      expect(<int>[small.image.width, small.image.height], <int>[14, 10]);

      final ImageInfo wide = await _resolve(tester, BoxSizedImage(MemoryImage(Uint8List.fromList(_png40x30)), width: 20, height: 5));
      expect(<int>[wide.image.width, wide.image.height], <int>[20, 15]);

      final ImageInfo big = await _resolve(tester, BoxSizedImage(MemoryImage(Uint8List.fromList(_png40x30)), width: 400, height: 400));
      expect(<int>[big.image.width, big.image.height], <int>[40, 30], reason: 'never upscaled');
    });

    testWidgets('a box without a usable size leaves the image untouched', (WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (BuildContext c) {
        context = c;
        return const SizedBox();
      }));
      final MemoryImage source = MemoryImage(Uint8List.fromList(_png40x30));
      expect(identical(BoxSizedImage.forBox(context, source, width: double.infinity, height: 80), source), isTrue);
      expect(BoxSizedImage.forBox(context, source, width: 80, height: 80), isA<BoxSizedImage>());
    });

    test('every picked-photo preview on the forms is sized for its box', () {
      const Map<String, int> previews = <String, int>{
        'lib/app/product_screens/add_product_screen.dart': 1,
        'lib/app/add_restaurant_screen/add_restaurant_screen.dart': 1,
        'lib/app/dine_in_screen/dine_in_create_screen.dart': 1,
        'lib/app/offer_screens/add_edit_offer_screen.dart': 1,
        'lib/app/add_story_screen/add_story_screen.dart': 1,
        'lib/app/edit_profile_screen/edit_profile_screen.dart': 1,
        'lib/app/add_advertisement_screen/add_advertisement_screen.dart': 2,
        'lib/app/verification_screen/verification_details_upload_screen.dart': 2,
      };
      previews.forEach((String path, int count) {
        final String source = code(path);
        expect(source.contains('Image.file('), isFalse, reason: path);
        expect(RegExp(r'BoxSizedImage\.forBox\(context, FileImage\(File\(').allMatches(source).length, count, reason: path);
      });
      // The document photo is drawn into the 90%-wide box around it.
      final String verification = code('lib/app/verification_screen/verification_details_upload_screen.dart');
      expect(RegExp(r'BoxSizedImage\.forBox\(context, FileImage\(File\(controller\.(front|back)Image\.value\)\), width: Responsive\.width\(90, context\)').allMatches(verification).length, 2);
    });
  });

  group('dialogs and animations', () {
    test('the log-out and delete-account GIFs are decoded at their drawn size', () {
      final String profile = code('lib/app/profile_screen/profile_screen.dart');
      for (final String gif in <String>['assets/images/ic_logout.gif', 'assets/icons/delete_dialog.gif']) {
        final int at = profile.indexOf("Image.asset('$gif'");
        expect(at, isNot(-1), reason: gif);
        final String call = profile.substring(at, profile.indexOf('\n', at));
        expect(call.contains('cacheWidth: (50 * MediaQuery.devicePixelRatioOf(context)).ceil()'), isTrue, reason: gif);
        expect(call.contains('cacheHeight: (50 * MediaQuery.devicePixelRatioOf(context)).ceil()'), isTrue, reason: gif);
      }
    });

    testWidgets('the animated border only asks for frames while it is loading', (WidgetTester tester) async {
      Widget border(bool loading) => MaterialApp(home: AnimatedBorderContainer(isLoading: loading, child: const Text('field')));

      await tester.pumpWidget(border(false));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'an idle form used to repaint every frame');

      await tester.pumpWidget(border(true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.pumpWidget(border(false));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('admin catalogue search', () {
    test('one change per keystroke, with the same matches in the same order', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final AdminProductController controller = AdminProductController();
      controller.allProductList.assignAll(<ProductModel>[
        for (int i = 0; i < 60; i++) ProductModel(id: 'p$i', name: i % 3 == 0 ? 'Pizza $i' : 'Burger $i'),
      ]);
      int changes = 0;
      final Worker worker = ever<List<ProductModel>>(controller.productList, (_) => changes++);

      controller.onSearchTextChanged('PIZZA');
      await Future<void>.delayed(Duration.zero);
      expect(controller.productList.map((ProductModel p) => p.id).toList(), <String>[for (int i = 0; i < 60; i += 3) 'p$i']);
      expect(changes, 1, reason: 'clearing and adding one by one notified the screen once per product');

      changes = 0;
      controller.onSearchTextChanged('');
      await Future<void>.delayed(Duration.zero);
      expect(controller.productList.length, 60);
      expect(changes, 1);
      worker.dispose();
    });

    test('the catalogue list is not shrink-wrapped', () {
      final String screen = code('lib/app/product_screens/admin_product_screen.dart');
      final int list = screen.indexOf('itemCount: controller.productList.length,');
      expect(list, isNot(-1));
      expect(screen.substring(list, screen.indexOf('itemBuilder:', list)).contains('shrinkWrap'), isFalse);
    });
  });

  group('home tab', () {
    testWidgets('while the first load is still filling, an empty tab shows the loader, then its message', (WidgetTester tester) async {
      final _FillingHomeController controller = _FillingHomeController();
      Widget tab() => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: GetX<_FillingHomeController>(
              init: controller,
              global: false,
              builder: (_) => const HomeScreen().orderTab(controller, false, orders: <OrderModel>[].obs, emptyMessage: 'Nothing here', card: (_, _) => const SizedBox()),
            ),
          ),
        ),
      );

      controller.isFillingOrders.value = true;
      await tester.pumpWidget(tab());
      expect(find.text('Nothing here'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.isFillingOrders.value = false;
      await tester.pump();
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    test('Home appears after the first page; the top-up carries on and clears the flag', () {
      final String getOrder = method(code('lib/controller/home_controller.dart'), 'Future<void> getOrder()');
      final int firstPage = getOrder.indexOf('final Future<void> firstPage = _firstPageShown(paginator);');
      final int refresh = getOrder.indexOf('final Future<void> loading = paginator.refresh();');
      expect(firstPage, isNot(-1));
      expect(refresh, greaterThan(firstPage), reason: 'the watcher must exist before the first delivery can land');
      expect(getOrder.contains('await Future.any<void>(<Future<void>>[loading, firstPage]);'), isTrue);
      expect(getOrder.contains('if (identical(ordersPaginator, paginator)) isFillingOrders.value = false;'), isTrue);
      expect(getOrder.contains('await paginator.refresh();'), isFalse);
      // The tab still waits for this before lifting its spinner.
      expect(method(code('lib/controller/home_controller.dart'), 'Future<void> getUserProfile()').contains('reads.add(getOrder());'), isTrue);
    });

    test('accepting with an estimated time no longer waits for the push to be delivered', () {
      final String home = code('lib/app/Home_screen/home_screen.dart');
      expect(RegExp(r'await\s+SendNotification\.').hasMatch(home), isFalse);
      expect(home.contains('SendNotification.sendFcmMessage(Constant.restaurantAccepted, orderModel.author!.fcmToken.toString(), {});'), isTrue);
    });
  });

  group('reads started together', () {
    test('admin inbox: one advert read per conversation, kept across rebuilds', () {
      final String inbox = code('lib/app/chat_screens/admin_inbox_screen.dart');
      expect(inbox.contains('_advertReads.putIfAbsent(advertisementId,'), isTrue);
      expect(inbox.contains('future: _advertFor(inboxModel.orderId!)'), isTrue);
      expect(inbox.contains('future: FireStoreUtils.getAdvertisementById('), isFalse);
    });

    test('subscription plans: settings, profile and sections together; store alongside the plan list', () {
      final String init = method(code('lib/controller/subscription_controller.dart'), 'Future<void> getInitPlanSettings()');
      final int firstAwait = init.indexOf('await ');
      for (final String start in <String>[
        "Concurrent.start(FireStoreUtils.fireStore.collection(CollectionName.settings).doc('vendor').get())",
        'Concurrent.start(FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()))',
        'Concurrent.start(FireStoreUtils.getSection())',
      ]) {
        final int at = init.indexOf(start);
        expect(at, isNot(-1), reason: start);
        expect(at, lessThan(firstAwait), reason: start);
      }
      // Applied in the original order.
      expect(init.indexOf('await vendorSettingsRead.then'), lessThan(init.indexOf('await profileRead')));
      expect(init.indexOf('await profileRead'), lessThan(init.indexOf('await sectionsRead.then')));
      final int planList = init.indexOf('Concurrent.start(getSubscriptionPlanList())');
      expect(planList, greaterThan(init.indexOf('await sectionsRead.then')));
      expect(init.indexOf('await storeRead!.then'), greaterThan(planList));
      expect(init.indexOf('await planListRead;'), greaterThan(init.indexOf('await storeRead!.then')));
      expect(init.indexOf('await planListRead;'), lessThan(init.indexOf('isLoading.value = false')));
    });

    test('adverts: the list is requested with the store and still applied after it', () {
      final String init = method(code('lib/controller/advertisement_list_controller.dart'), 'Future<void> initCall()');
      expect(init.indexOf('Concurrent.start(FireStoreUtils.getAdvertisement())'), lessThan(init.indexOf('await getVendor();')));
      expect(init.indexOf('getAdvertisement(prefetched: advertsRead);'), greaterThan(init.indexOf('await getVendor();')));
    });

    test('story: the settings read runs alongside the story read', () {
      final String story = method(code('lib/controller/add_story_controller.dart'), 'Future<void> getStory()');
      final int settings = story.indexOf("final Future<DocumentSnapshot<Map<String, dynamic>>> settingsRead = Concurrent.start(");
      expect(settings, isNot(-1));
      expect(settings, lessThan(story.indexOf('await FireStoreUtils.getStory(')));
      expect(story.indexOf('await settingsRead;'), greaterThan(story.indexOf('await FireStoreUtils.getStory(')));
      expect(story.indexOf('await settingsRead;'), lessThan(story.indexOf('isLoading.value = false')));
    });

    test('apply tax: the product writes are sent together and awaited', () {
      final String screen = code('lib/app/product_screens/product_list_screen.dart');
      expect(screen.contains('await FireStoreUtils.updateProduct(product);'), isFalse);
      final int wait = screen.indexOf('await Future.wait<bool>(<Future<bool>>[');
      expect(wait, isNot(-1));
      expect(screen.indexOf('return FireStoreUtils.updateProduct(product);'), greaterThan(wait));
      expect(screen.indexOf('controller.clearSelection();'), greaterThan(wait));
    });
  });

  group('writes and logging', () {
    test('a saved profile is remembered as written, only when the save succeeded', () {
      final String update = method(code('lib/utils/fire_store_utils.dart'), 'static Future<bool> updateUser(UserModel userModel)');
      final int remember = update.indexOf('_rememberUser(userModel.id!, userModel.toJson());');
      expect(remember, greaterThan(update.indexOf('.catchError(')));
      expect(update.indexOf('if (isUpdate && userModel.id != null) {'), lessThan(remember));
      expect(update.indexOf('UserCache.invalidate(userModel.id);'), lessThan(update.indexOf('.set(userModel.toJson())')));
    });

    test('chat messages are marked seen together, not one round trip at a time', () {
      final String utils = code('lib/utils/fire_store_utils.dart');
      expect(utils.contains('await doc.reference.update('), isFalse);
      expect(RegExp(r'_markSeen\(querySnapshot\.docs\);').allMatches(utils).length, 2);
      final String mark = method(utils, 'static void _markSeen(');
      expect(mark.contains("doc.reference.update({'seen': true})"), isTrue);
    });

    test('push tokens, push responses and whole documents are printed in debug builds only', () {
      final String push = code('lib/constant/send_notification.dart');
      expect(RegExp(r'^\s*debugPrint\(accessToken\);', multiLine: true).allMatches(push).length, 2);
      expect(RegExp(r'if \(kDebugMode\) \{\s*debugPrint\("accessToken=======>"\);\s*debugPrint\(accessToken\);').allMatches(push).length, 2);
      expect(RegExp(r'if \(kDebugMode\) \{\s*debugPrint\("Notification=======>"\);').allMatches(push).length, 3);
      final String utils = code('lib/utils/fire_store_utils.dart');
      expect(RegExp(r'^\s*print\(value\.docs\.first\.data\(\)\);', multiLine: true).hasMatch(utils), isFalse);
      expect(RegExp(r'^\s*print\(element\.data\(\)\);', multiLine: true).hasMatch(utils), isFalse);
    });

    test('printing a receipt no longer base64-encodes and logs the whole ticket', () {
      expect(code('lib/controller/order_details_controller.dart').contains('base64Encode('), isFalse);
    });
  });
}
