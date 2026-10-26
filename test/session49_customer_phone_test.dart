import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/utils/customer_phone.dart';

/// Session 49 - after the store accepts an order, it sees the customer's
/// mobile number, so the two can reach each other about that delivery.
void main() {
  String read(String path) => File(path).readAsStringSync();

  String code(String source) => source.split('\n').where((String line) => !line.trimLeft().startsWith('//')).join('\n');

  /// The part of the Home screen between two card builders.
  String between(String source, String from, String to) {
    final int start = source.indexOf(from);
    final int end = source.indexOf(to);
    expect(start, greaterThan(-1), reason: '$from is missing');
    expect(end, greaterThan(start), reason: '$to is missing');
    return source.substring(start, end);
  }

  group('the number shown', () {
    test('a number stored apart from its code is shown together with it', () {
      expect(customerPhoneText(UserModel(countryCode: '+92', phoneNumber: '3001234567')), '+92 3001234567');
    });

    test('a number that already carries its code is shown as it is', () {
      expect(customerPhoneText(UserModel(countryCode: '+92', phoneNumber: '+923001234567')), '+923001234567');
    });

    test('no code - the number alone', () {
      expect(customerPhoneText(UserModel(phoneNumber: '3001234567')), '3001234567');
      expect(customerPhoneText(UserModel(countryCode: ' ', phoneNumber: ' 3001234567 ')), '3001234567');
    });

    test('no number - nothing, so the line is hidden', () {
      expect(customerPhoneText(UserModel(countryCode: '+92', phoneNumber: '')), '');
      expect(customerPhoneText(UserModel(countryCode: '+92')), '');
      expect(customerPhoneText(null), '');
    });
  });

  group('where it is shown', () {
    final String home = code(read('lib/app/Home_screen/home_screen.dart'));

    test('once, on the accepted order card, under the customer\'s name', () {
      expect('customerPhoneText('.allMatches(home).length, 2, reason: 'one visibility check and one Text, nothing more');

      final String accepted = between(home, 'InkWell acceptedWidget(', 'InkWell completedAndRejectedWidget(');
      final int name = accepted.indexOf('orderModel.author!.fullName().toString().tr,');
      final int phone = accepted.indexOf('customerPhoneText(orderModel.author)');
      final int address = accepted.indexOf('orderModel.address!.getFullAddress().tr,');
      expect(name, greaterThan(-1));
      expect(phone, greaterThan(name), reason: 'under the name');
      expect(phone, lessThan(address), reason: 'above the address');
    });

    test('not on the new-order card, and not on the completed or rejected card', () {
      final String newCard = between(home, 'InkWell newOrderWidget(', 'InkWell acceptedWidget(');
      final int completedAt = home.indexOf('InkWell completedAndRejectedWidget(');
      expect(newCard.contains('customerPhoneText('), isFalse, reason: 'the number appears after the order is accepted');
      expect(home.indexOf('customerPhoneText(', completedAt), -1, reason: 'the completed / rejected card is unchanged');
    });
  });
}
