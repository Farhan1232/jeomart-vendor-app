// ignore_for_file: non_constant_identifier_names

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:vendor/constant/constant.dart';
import 'package:vendor/models/notification_model.dart';
import 'package:vendor/utils/fire_store_utils.dart';

class SendNotification {
  static final _scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  static Future getCharacters() {
    return http.get(Uri.parse(Constant.jsonNotificationFileURL.toString()));
  }

  /// The last access token minted, and the service-account file it came from.
  static AccessCredentials? _credentials;
  static String? _credentialsSource;

  /// A mint already in progress, shared by every send that arrives meanwhile.
  static Future<AccessCredentials>? _minting;

  /// A token this close to expiry is replaced rather than used.
  static const Duration _refreshMargin = Duration(minutes: 5);

  /// An OAuth access token for the FCM v1 API.
  ///
  /// This used to download the service-account file and mint a brand-new token
  /// - an RSA signature plus a round trip to Google - for **every** notification,
  /// and leave the HTTP client it minted with open. Accepting one order sends
  /// two notifications, every chat message sends one, so each of those buttons
  /// paid two to three extra network round trips before the push went out (one
  /// of them, the estimated-time dialog, waits for it).
  ///
  /// The token Google hands back is valid for an hour. It is now kept and reused
  /// until five minutes before it expires, or until the service-account URL
  /// changes, and the client is closed. The message that is sent is identical.
  static Future<String> getAccessToken() async {
    final String source = Constant.jsonNotificationFileURL.toString();
    final AccessCredentials? cached = _credentials;
    if (cached != null && _credentialsSource == source && cached.accessToken.expiry.isAfter(DateTime.now().toUtc().add(_refreshMargin))) {
      return cached.accessToken.data;
    }
    final AccessCredentials credentials = await (_minting ??= _mintAccessToken(source).whenComplete(() => _minting = null));
    return credentials.accessToken.data;
  }

  static Future<AccessCredentials> _mintAccessToken(String source) async {
    Map<String, dynamic> jsonData = {};

    await getCharacters().then((response) {
      jsonData = json.decode(response.body);
    });
    final serviceAccountCredentials = ServiceAccountCredentials.fromJson(jsonData);

    final client = await clientViaServiceAccount(serviceAccountCredentials, _scopes);
    final AccessCredentials credentials = client.credentials;
    client.close();
    _credentials = credentials;
    _credentialsSource = source;
    return credentials;
  }

  static Future<bool> sendFcmMessage(String type, String token, Map<String, dynamic>? payload) async {
    if (kDebugMode) print(type);
    try {
      // The token and the notification text do not depend on each other.
      final List<Object?> prepared = await Future.wait<Object?>([getAccessToken(), FireStoreUtils.getNotificationContent(type)]);
      final String accessToken = prepared[0] as String;
      if (kDebugMode) {
        debugPrint("accessToken=======>");
        debugPrint(accessToken);
      }
      NotificationModel? notificationModel = prepared[1] as NotificationModel?;

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/${Constant.senderId}/messages:send'),
        headers: <String, String>{'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'},
        body: jsonEncode(<String, dynamic>{
          'message': {
            'token': token,
            'notification': {'body': notificationModel!.message ?? '', 'title': notificationModel.subject ?? ''},
            'data': payload,
          },
        }),
      );

      if (kDebugMode) {
        debugPrint("Notification=======>");
        debugPrint(response.statusCode.toString());
        debugPrint(response.body);
      }
      return true;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  static Future<bool> sendOneNotification({required String token, required String title, required String body, required Map<String, dynamic> payload}) async {
    try {
      final String accessToken = await getAccessToken();
      if (kDebugMode) {
        debugPrint("accessToken=======>");
        debugPrint(accessToken);
      }

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/${Constant.senderId}/messages:send'),
        headers: <String, String>{'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'},
        body: jsonEncode(<String, dynamic>{
          'message': {
            'token': token,
            'notification': {'body': body, 'title': title},
            'data': payload,
          },
        }),
      );

      if (kDebugMode) {
        debugPrint("Notification=======>");
        debugPrint(response.statusCode.toString());
        debugPrint(response.body);
      }
      return true;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  static Future<bool> sendChatFcmMessage(String title, String message, String token, Map<String, dynamic>? payload) async {
    try {
      final String accessToken = await getAccessToken();
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/${Constant.senderId}/messages:send'),
        headers: <String, String>{'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'},
        body: jsonEncode(<String, dynamic>{
          'message': {
            'token': token,
            'notification': {'body': message, 'title': title},
            'data': payload,
          },
        }),
      );
      if (kDebugMode) {
        debugPrint("Notification=======>");
        debugPrint(response.statusCode.toString());
        debugPrint(response.body);
      }
      return true;
    } catch (e) {
      print("error :::::::::::$e");
      return false;
    }
  }
}
