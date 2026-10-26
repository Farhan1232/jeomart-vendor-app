import 'package:vendor/models/user_model.dart';

/// The customer's mobile number as the store sees it on an accepted order, so
/// the two can reach each other if anything goes wrong with the delivery.
///
/// Orders carry the number and the country code in separate fields, and some
/// are already stored with the code (`+92…`), so a number that starts with `+`
/// is shown as it is. Nothing is returned when there is no number - the caller
/// hides the line.
String customerPhoneText(UserModel? customer) {
  final String number = (customer?.phoneNumber ?? '').trim();
  if (number.isEmpty) return '';
  final String code = (customer?.countryCode ?? '').trim();
  if (code.isEmpty || number.startsWith('+')) return number;
  return '$code $number';
}
