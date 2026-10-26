import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/constant/send_notification.dart';
import 'package:vendor/models/conversation_model.dart';
import 'package:vendor/models/inbox_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/utils/fire_store_utils.dart';
import 'package:vendor/utils/shared_order_chat.dart';

class ChatController extends GetxController {
  Rx<TextEditingController> messageController = TextEditingController().obs;

  Rx<ScrollController> scrollController = ScrollController().obs;

  @override
  void onInit() {
    if (scrollController.value.hasClients) {
      Timer(const Duration(milliseconds: 500), () => scrollController.value.jumpTo(scrollController.value.position.minScrollExtent));
    }
    getArgument();
    super.onInit();
  }

  RxBool isLoading = true.obs;
  RxString orderId = "".obs;
  RxString receivedId = "".obs;
  RxString receivedName = "".obs;
  RxString receivedProfileUrl = "".obs;
  RxString senderId = "".obs;
  RxString senderName = "".obs;
  RxString senderProfileUrl = "".obs;
  RxString token = "".obs;
  RxString chatType = "".obs;
  RxString sectionType = "".obs;
  Rx<UserModel?> receiverUser = UserModel().obs;

  /// Set when this chat belongs to a store order: one conversation for the
  /// customer, the store and the driver. Null for every other chat.
  Rxn<SharedOrderChat> sharedChat = Rxn<SharedOrderChat>();
  Future<SharedOrderChat?>? _sharedChatLoad;

  Future<void> getArgument() async {
    dynamic argumentData = Get.arguments;
    if (argumentData != null) {
      sectionType.value = argumentData['sectionType'] ?? '';
      orderId.value = argumentData['orderId'] ?? '';
      receivedId.value = argumentData['receivedId'] ?? '';
      receivedName.value = argumentData['receivedName'] ?? '';
      receivedProfileUrl.value = argumentData['receivedProfileUrl'] ?? "";
      senderId.value = argumentData['senderId'] ?? '';
      senderName.value = argumentData['senderName'] ?? '';
      senderProfileUrl.value = argumentData['senderProfileUrl'] ?? "";
      token.value = argumentData['token'] ?? '';
      chatType.value = argumentData['chatType'] ?? '';
      // Only an order chat with a customer can be shared - not the admin or
      // advertisement chats. The lookup runs beside the rest of the opening.
      if (chatType.value == Constant.userRoleVendor && receivedId.value != 'admin') {
        _sharedChatLoad = _loadSharedChat();
      }
      if (receivedId.value != 'admin') {
        receiverUser.value = await FireStoreUtils.getUserProfile(receivedId.value);
      }
    }
    setSeen();

    isLoading.value = false;
  }

  Future<SharedOrderChat?> _loadSharedChat() async {
    final SharedOrderChat? chat = await SharedOrderChat.load(orderId.value);
    if (!isClosed) sharedChat.value = chat;
    return chat;
  }

  Future<void> setSeen() async {
    FireStoreUtils.setSeenChatForOrder(orderId: orderId.value);
  }

  Future<void> sendMessage(String message, Url? url, String videoThumbnail, String messageType) async {
    // Read before anything is awaited: the send button clears the field right
    // after calling this.
    final String typedText = messageController.value.text;
    SharedOrderChat? shared = sharedChat.value;
    if (shared == null && _sharedChatLoad != null) shared = await _sharedChatLoad;
    if (shared != null) {
      await shared.send(
        _orderMessage(message, url, videoThumbnail, messageType),
        senderRole: SharedOrderChat.store,
        fallbackName: senderName.value,
        lastMessage: typedText,
        lastMessageType: messageType,
      );
      return;
    }

    List<String> senderReceiverId = [receivedId.value, senderId.value];
    InboxModel inboxModel = InboxModel(
      chatType: chatType.value,
      senderReceiverId: senderReceiverId,
      lastSenderId: senderId.value,
      senderId: senderId.value,
      receiverId: receivedId.value,
      createdAt: Timestamp.now(),
      orderId: orderId.value,
      lastMessage: typedText,
      lastMessageType: messageType,
      type: chatType.value == 'admin' ? 'admin' : 'orderChat',
    );

    FireStoreUtils.addInbox(inboxModel);

    ConversationModel conversationModel = ConversationModel(
      id: const Uuid().v4(),
      message: message,
      senderId: FireStoreUtils.getCurrentUid(),
      receiverId: receivedId.value,
      createdAt: Timestamp.now(),
      url: url,
      orderId: orderId.value,
      messageType: messageType,
      videoThumbnail: videoThumbnail,
      seen: false,
    );

    if (url != null) {
      if (url.mime.contains('image')) {
        conversationModel.message = "sent a message".tr;
      } else if (url.mime.contains('video')) {
        conversationModel.message = "Sent a video".tr;
      } else if (url.mime.contains('audio')) {
        conversationModel.message = "Sent a audio".tr;
      }
    }

    FireStoreUtils.addChat(conversationModel);
    log("receiverUser.value :: ${receiverUser.value?.fullName()} :: ${conversationModel.message.toString()} :: ${receiverUser.value?.fcmToken} :: ${inboxModel.type} :: ${inboxModel.chatType}");
    if (receiverUser.value?.fcmToken != null) {
      SendNotification.sendChatFcmMessage(receivedName.value, conversationModel.message.toString(), receiverUser.value?.fcmToken ?? '', {
        'type': inboxModel.type,
        'chatType': inboxModel.chatType,
        'orderId': orderId.value,
        'senderId': FireStoreUtils.getCurrentUid(),
      });
    }
  }

  /// A message for an order's shared chat, built the way [sendMessage] builds
  /// every other message.
  ConversationModel _orderMessage(String message, Url? url, String videoThumbnail, String messageType) {
    final ConversationModel conversationModel = ConversationModel(
      id: const Uuid().v4(),
      message: message,
      senderId: FireStoreUtils.getCurrentUid(),
      receiverId: receivedId.value,
      createdAt: Timestamp.now(),
      url: url,
      orderId: orderId.value,
      messageType: messageType,
      videoThumbnail: videoThumbnail,
      seen: false,
    );
    if (url != null) {
      if (url.mime.contains('image')) {
        conversationModel.message = "sent a message".tr;
      } else if (url.mime.contains('video')) {
        conversationModel.message = "Sent a video".tr;
      } else if (url.mime.contains('audio')) {
        conversationModel.message = "Sent a audio".tr;
      }
    }
    return conversationModel;
  }

  final ImagePicker imagePicker = ImagePicker();

  // Future pickFile({required ImageSource source}) async {
  //   try {
  //     XFile? image = await imagePicker.pickImage(source: source);
  //     if (image == null) return;
  //     Url url = await FireStoreUtils.uploadChatImageToFireStorage(File(image.path), Get.context!);
  //     sendMessage('', url, '', 'image');
  //     Get.back();
  //   } on PlatformException catch (e) {
  //     ShowToastDialog.showToast("${"failed_to_pick".tr} : \n $e");
  //   }
  // }
}
