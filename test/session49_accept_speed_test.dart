import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Session 49 - "when you press Accept it keeps loading".
///
/// Accepting waited for the order write, then the first wallet record, then the
/// second, then the balance - one after another, with the loader up for the sum
/// of them. The independent writes now go together. Every record written, and
/// the values in it, are unchanged.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String code(String source) => source.split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

  String bodyOf(String source, String signature, {String endsBefore = '\n  }\n'}) {
    final int start = source.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature is missing');
    final int end = source.indexOf(endsBefore, start);
    return source.substring(start, end == -1 ? source.length : end);
  }

  group('the store accepting an order', () {
    final String home = code(read('lib/app/Home_screen/home_screen.dart'));
    final int accept = home.indexOf("orderModel.status = Constant.orderAccepted;\n                                            await AudioPlayerService.playSound(false);");

    test('sends the order and the earnings at once, and still sends both', () {
      expect(accept, greaterThan(-1), reason: 'the Accept branch changed shape');
      final String branch = home.substring(accept, home.indexOf('ShowToastDialog.closeLoader();', accept));

      expect(branch, contains('await Future.wait(<Future<void>>['));
      expect(branch, contains('FireStoreUtils.updateOrder(orderModel),'));
      expect(branch, contains('FireStoreUtils.restaurantVendorWalletSet(orderModel),'));
      expect('await '.allMatches(branch).length, 2,
          reason: 'only the sound and the one Future.wait are waited for: ${branch.trim()}');
    });

    test('the order is still marked accepted before anything is sent', () {
      final String branch = home.substring(accept, home.indexOf('ShowToastDialog.closeLoader();', accept));
      expect(branch.indexOf('orderModel.status = Constant.orderAccepted;'), lessThan(branch.indexOf('Future.wait')));
    });

    test('the push to the customer is still sent without holding the loader', () {
      final String branch = home.substring(accept, home.indexOf('ShowToastDialog.closeLoader();', accept));
      expect(branch, contains('SendNotification.sendFcmMessage(Constant.restaurantAccepted, orderModel.author!.fcmToken.toString(), {});'));
      expect(branch.contains('await SendNotification'), isFalse);
    });
  });

  group('the store\'s earnings for an order', () {
    String walletBody() => bodyOf(code(read('lib/utils/fire_store_utils.dart')), 'static Future restaurantVendorWalletSet(OrderModel orderModel) async {');

    test('both wallet records go together, and the balance after them', () {
      final String body = walletBody();
      expect(body, contains('await Future.wait(<Future<void>>['));
      expect(body, contains('.doc(historyModel.id).set(historyModel.toJson())'));
      expect(body, contains('.doc(taxModel.id).set(taxModel.toJson())'));
      expect(body.indexOf('Future.wait'), lessThan(body.indexOf('await updateUserWallet(')),
          reason: 'the records are written before the balance moves, as before');
    });

    test('the records and the amounts are untouched', () {
      final String body = walletBody();
      expect(body, contains('note: "Order Amount credited"'));
      expect(body, contains('note: "Order Tax credited"'));
      expect(body, contains('amount: basePrice,'));
      expect(body, contains('amount: totalTaxAmount,'));
      expect(body, contains("await updateUserWallet(amount: (basePrice + totalTaxAmount).toString(), userId: orderModel.vendor!.author.toString());"));
    });
  });
}
