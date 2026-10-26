import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vendor/themes/theme_controller.dart';
import 'package:vendor/app/chat_screens/chat_screen.dart';
import 'package:vendor/constant/collection_name.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/constant/show_toast_dialog.dart';
import 'package:vendor/models/advertisement_model.dart';
import 'package:vendor/models/inbox_model.dart';
import 'package:vendor/models/vendor_model.dart';
import 'package:vendor/themes/app_them_data.dart';
import 'package:vendor/themes/responsive.dart';
import 'package:vendor/utils/fire_store_utils.dart';
import 'package:vendor/utils/network_image_widget.dart';
import 'package:vendor/widget/firebase_pagination/src/firestore_pagination.dart';
import 'package:vendor/widget/firebase_pagination/src/models/view_type.dart';

class AdminInboxScreen extends StatefulWidget {
  const AdminInboxScreen({super.key});

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen> {
  /// One advert read per conversation for as long as the inbox is open.
  ///
  /// Each row's `FutureBuilder` used to be handed a brand-new
  /// `getAdvertisementById(...)` future on every rebuild - and this live list
  /// rebuilds on every update to any conversation (and twice while opening).
  /// A new future puts the row back to `waiting`, drawn as an empty text, so
  /// every update blanked the inbox for a frame and re-read every visible
  /// advert. The restaurant inbox got the same fix in Session 35.
  final Map<String, Future<AdvertisementModel>> _advertReads = <String, Future<AdvertisementModel>>{};

  Future<AdvertisementModel> _advertFor(String advertisementId) {
    return _advertReads.putIfAbsent(advertisementId, () => FireStoreUtils.getAdvertisementById(advertisementId: advertisementId));
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final isDark = themeController.isDark.value;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? AppThemeData.surfaceDark : AppThemeData.surface,
        centerTitle: false,
        titleSpacing: 0,
        title: Text(
          "Admin Chat Inbox".tr,
          textAlign: TextAlign.start,
          style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 16, color: isDark ? AppThemeData.grey50 : AppThemeData.grey900),
        ),
      ),
      body: FirestorePagination(
        //item builder type is compulsory.
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, documentSnapshots, index) {
          final data = documentSnapshots[index].data() as Map<String, dynamic>?;
          InboxModel inboxModel = InboxModel.fromJson(data!);
          return InkWell(
            onTap: () async {
              ShowToastDialog.showLoader("Please wait".tr);
              VendorModel? vendorModel = await FireStoreUtils.getVendorById(Constant.userModel!.vendorID.toString());
              ShowToastDialog.closeLoader();

              Get.to(
                const ChatScreen(),
                arguments: {
                  "senderName": vendorModel?.title,
                  "senderId": Constant.userModel?.id,
                  "senderProfileUrl": vendorModel?.photo,
                  "receivedName": 'Admin',
                  "receivedId": 'admin',
                  "receivedProfileUrl": '',
                  "orderId": inboxModel.orderId,
                  "token": '',
                  "chatType": 'admin',
                },
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Container(
                decoration: ShapeDecoration(
                  color: isDark ? AppThemeData.grey900 : AppThemeData.grey50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: FutureBuilder(
                    future: _advertFor(inboxModel.orderId!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done) {
                        AdvertisementModel advertisementModel = snapshot.data!;
                        return Row(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.all(Radius.circular(10)),
                              child: NetworkImageWidget(
                                imageUrl: advertisementModel.profileImage.toString(),
                                fit: BoxFit.cover,
                                height: Responsive.height(6, context),
                                width: Responsive.width(12, context),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "${advertisementModel.title}",
                                          textAlign: TextAlign.start,
                                          style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 16, color: isDark ? AppThemeData.grey100 : AppThemeData.grey800),
                                        ),
                                      ),
                                      Text(
                                        Constant.timestampToDate(inboxModel.createdAt!),
                                        textAlign: TextAlign.start,
                                        style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 16, color: isDark ? AppThemeData.grey400 : AppThemeData.grey500),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    "${inboxModel.lastMessage}",
                                    textAlign: TextAlign.start,
                                    style: TextStyle(fontFamily: AppThemeData.medium, fontSize: 14, color: isDark ? AppThemeData.grey200 : AppThemeData.grey700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Text(
                          "",
                          textAlign: TextAlign.start,
                          style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 14, color: isDark ? AppThemeData.grey400 : AppThemeData.grey500),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          );
        },
        onEmpty: Constant.showEmptyView(message: "No Conversion found".tr, isDark: isDark),
        // orderBy is compulsory to enable pagination
        query: FireStoreUtils.fireStore.collection(CollectionName.chatAdmin).where("restaurantId", isEqualTo: FireStoreUtils.getCurrentUid()).orderBy('createdAt', descending: true),
        //Change types customerId
        initialLoader: Constant.loader(),
        // to fetch real-time data
        isLive: true,
        viewType: ViewType.list,
      ),
    );
  }
}
