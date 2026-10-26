import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/constant/show_toast_dialog.dart';
import 'package:vendor/models/section_model.dart';
import 'package:vendor/models/tax_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/models/vendor_category_model.dart';
import 'package:vendor/models/vendor_model.dart';
import 'package:vendor/models/zone_model.dart';
import 'package:vendor/utils/concurrent.dart';
import 'package:vendor/utils/fire_store_utils.dart';
import 'package:vendor/widget/geoflutterfire/src/geoflutterfire.dart';

class AddRestaurantController extends GetxController {
  RxBool isLoading = true.obs;
  RxBool isAddressEnable = false.obs;
  RxBool isEnableDeliverySettings = true.obs;
  final myKey1 = GlobalKey<DropdownSearchState<VendorCategoryModel>>();

  Rx<TextEditingController> restaurantNameController = TextEditingController().obs;
  Rx<TextEditingController> restaurantDescriptionController = TextEditingController().obs;
  Rx<TextEditingController> mobileNumberController = TextEditingController().obs;
  Rx<TextEditingController> countryCodeEditingController = TextEditingController().obs;
  Rx<TextEditingController> countryISOCodeEditingController = TextEditingController().obs;
  Rx<TextEditingController> addressController = TextEditingController().obs;

  Rx<TextEditingController> chargePerKmController = TextEditingController().obs;
  Rx<TextEditingController> minDeliveryChargesController = TextEditingController().obs;
  Rx<TextEditingController> minDeliveryChargesWithinKMController = TextEditingController().obs;

  Rx<TextEditingController> packagingChargeAmountController = TextEditingController().obs;

  LatLng? selectedLocation;

  RxList images = <dynamic>[].obs;

  RxList<VendorCategoryModel> vendorCategoryList = <VendorCategoryModel>[].obs;
  RxList<ZoneModel> zoneList = <ZoneModel>[].obs;
  Rx<ZoneModel> selectedZone = ZoneModel().obs;

  // Rx<VendorCategoryModel> selectedCategory = VendorCategoryModel().obs;
  RxList selectedService = [].obs;

  RxList<VendorCategoryModel> selectedCategories = <VendorCategoryModel>[].obs;

  RxBool canShowQRCodeButton = false.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getRestaurant();
    super.onInit();
  }

  Rx<UserModel> userModel = UserModel().obs;
  Rx<VendorModel> vendorModel = VendorModel().obs;
  Rx<DeliveryCharge> deliveryChargeModel = DeliveryCharge().obs;
  RxBool isSelfDelivery = false.obs;
  RxList<SectionModel> sectionsList = <SectionModel>[].obs;
  Rx<SectionModel> selectedSectionModel = SectionModel().obs;

  Future<void> getRestaurant() async {
    try {
      await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((model) {
        if (model != null) {
          userModel.value = model;
        }
      });
      // The QR-code button's condition, checked as soon as the profile is here.
      // It used to be checked once, on a three-second timer, so on a slow
      // connection the profile arrived after the check and the button never
      // appeared for a plan that includes it.
      if (userModel.value.subscriptionPlan?.features?.qrCodeGenerate == true) {
        canShowQRCodeButton.value = true;
      }

      // Everything below needs only the profile, not each other, so all five
      // reads start now instead of one after another. The results are still
      // applied in exactly the original order, and a failure still stops the
      // steps after it at the same place.
      final sectionsRead = Concurrent.start(FireStoreUtils.getSection());
      final categoriesRead = Concurrent.start(FireStoreUtils.getVendorCategoryById(userModel.value.sectionId.toString()));
      final zonesRead = Concurrent.start(FireStoreUtils.getZone(userModel.value.sectionId.toString()));
      final bool hasStore = Constant.userModel?.vendorID != null && Constant.userModel?.vendorID?.isNotEmpty == true;
      final vendorRead = hasStore ? Concurrent.start(FireStoreUtils.getVendorById(Constant.userModel!.vendorID.toString())) : null;
      final deliveryRead = Concurrent.start(FireStoreUtils.getDelivery());

      await sectionsRead.then((value) async {
        sectionsList.value = value.where((element) => element.serviceTypeFlag == "ecommerce-service" || element.serviceTypeFlag == "delivery-service").toList();
      });

      if (userModel.value.sectionId != null && userModel.value.sectionId!.isNotEmpty) {
        final matchingSections = sectionsList.where((element) => element.id == userModel.value.sectionId).toList();
        if (matchingSections.isNotEmpty) {
          selectedSectionModel.value = matchingSections.first;
        }
        // The same section id: `selectedSectionModel` is the section whose id equals userModel.sectionId.
        vendorCategoryList.value = await categoriesRead;
        if (vendorCategoryList.isEmpty) {
          ShowToastDialog.showToast("No category for this section".tr);
        }

        await zonesRead.then((value) {
          if (value != null) {
            zoneList.value = value;
          }
        });
      }

      if (vendorRead != null) {
        await vendorRead.then((value) {
          if (value != null) {
            vendorModel.value = value;

            restaurantNameController.value.text = vendorModel.value.title.toString();
            restaurantDescriptionController.value.text = vendorModel.value.description.toString();
            mobileNumberController.value.text = vendorModel.value.phonenumber.toString();
            addressController.value.text = vendorModel.value.location.toString();
            isSelfDelivery.value = vendorModel.value.isSelfDelivery ?? false;

            packagingChargeAmountController.value.text = vendorModel.value.packagingCharge != null ? vendorModel.value.packagingCharge.toString() : '0';

            if (addressController.value.text.isNotEmpty) {
              isAddressEnable.value = true;
            }
            if (vendorModel.value.latitude != null && vendorModel.value.longitude != null) {
              selectedLocation = LatLng(vendorModel.value.latitude!, vendorModel.value.longitude!);
            }
            for (var element in vendorModel.value.photos ?? []) {
              images.add(element);
            }

            for (var element in zoneList) {
              if (element.id == vendorModel.value.zoneId) {
                selectedZone.value = element;
              }
            }

            if (vendorModel.value.categoryID?.isNotEmpty == true) {
              selectedCategories.value = vendorCategoryList.where((category) => vendorModel.value.categoryID!.contains(category.id)).toList();
            }

            vendorModel.value.filters?.toJson().forEach((key, value) {
              if (value != null && value.toString().contains("Yes")) {
                selectedService.add(key);
              }
            });
          }
        });
      }

      await deliveryRead.then((value) {
        if (value != null) {
          deliveryChargeModel.value = value;
          isEnableDeliverySettings.value = deliveryChargeModel.value.vendorCanModify ?? false;
          if (value.vendorCanModify == true) {
            if (vendorModel.value.deliveryCharge != null) {
              chargePerKmController.value.text = vendorModel.value.deliveryCharge!.deliveryChargesPerKm.toString();
              minDeliveryChargesController.value.text = vendorModel.value.deliveryCharge!.minimumDeliveryCharges.toString();
              minDeliveryChargesWithinKMController.value.text = vendorModel.value.deliveryCharge!.minimumDeliveryChargesWithinKm.toString();
            }
          } else {
            chargePerKmController.value.text = deliveryChargeModel.value.deliveryChargesPerKm.toString();
            minDeliveryChargesController.value.text = deliveryChargeModel.value.minimumDeliveryCharges.toString();
            minDeliveryChargesWithinKMController.value.text = deliveryChargeModel.value.minimumDeliveryChargesWithinKm.toString();
          }
        }
      });
    } catch (e) {
      print(e);
    }

    isLoading.value = false;
  }

  Future<void> saveDetails() async {
    if (restaurantNameController.value.text.isEmpty) {
      ShowToastDialog.showToast("Please enter store name".tr);
    } else if (restaurantDescriptionController.value.text.isEmpty) {
      ShowToastDialog.showToast("Please enter Description".tr);
    } else if (mobileNumberController.value.text.isEmpty) {
      ShowToastDialog.showToast("Please enter phone number".tr);
    } else if (addressController.value.text.isEmpty) {
      ShowToastDialog.showToast("Please enter address".tr);
    } else if (selectedZone.value.id == null) {
      ShowToastDialog.showToast("Please select zone".tr);
    } else if (selectedCategories.isEmpty) {
      ShowToastDialog.showToast("Please select category".tr);
    } else if (selectedLocation == null) {
      ShowToastDialog.showToast("Please select the store address on the map (tap change next to Address)".tr);
    } else {
      // A zone saved without a drawn area cannot be checked; it used to crash the
      // Save button silently (null area) or reject every location (empty area).
      final List<GeoPoint>? zoneArea = selectedZone.value.area;
      final bool canCheckZone = zoneArea != null && zoneArea.length >= 3;
      if (!canCheckZone || Constant.isPointInPolygon(selectedLocation!, zoneArea)) {
        ShowToastDialog.showLoader("Please wait...".tr, longRunning: true);
        try {
        filter();
        DeliveryCharge deliveryChargeModel = DeliveryCharge(
          vendorCanModify: true,
          deliveryChargesPerKm: num.tryParse(chargePerKmController.value.text) ?? 0,
          minimumDeliveryCharges: num.tryParse(minDeliveryChargesController.value.text) ?? 0,
          minimumDeliveryChargesWithinKm: num.tryParse(minDeliveryChargesWithinKMController.value.text) ?? 0,
        );

        if (vendorModel.value.id == null) {
          vendorModel.value = VendorModel();
          vendorModel.value.createdAt = Timestamp.now();
        }
        for (int i = 0; i < images.length; i++) {
          if (images[i].runtimeType == XFile) {
            String url = await Constant.uploadUserImageToFireStorage(File(images[i].path), "profileImage/${FireStoreUtils.getCurrentUid()}", File(images[i].path).path.split('/').last);
            images.removeAt(i);
            images.insert(i, url);
          }
        }

        vendorModel.value.id = Constant.userModel?.vendorID;
        vendorModel.value.author = Constant.userModel!.id;
        vendorModel.value.authorName = Constant.userModel!.firstName;
        vendorModel.value.authorProfilePic = Constant.userModel!.profilePictureURL;

        vendorModel.value.categoryID = selectedCategories.map((e) => e.id ?? '').toList();
        vendorModel.value.categoryTitle = selectedCategories.map((e) => e.title ?? '').toList();
        vendorModel.value.g = G(
          geohash: Geoflutterfire().point(latitude: selectedLocation!.latitude, longitude: selectedLocation!.longitude).hash,
          geopoint: GeoPoint(selectedLocation!.latitude, selectedLocation!.longitude),
        );
        vendorModel.value.description = restaurantDescriptionController.value.text;
        vendorModel.value.phonenumber = mobileNumberController.value.text;
        vendorModel.value.filters = Filters.fromJson(filters);
        vendorModel.value.location = addressController.value.text;
        vendorModel.value.latitude = selectedLocation!.latitude;
        vendorModel.value.longitude = selectedLocation!.longitude;
        vendorModel.value.photos = images;
        vendorModel.value.sectionId = selectedSectionModel.value.id;
        if (images.isNotEmpty) {
          vendorModel.value.photo = images.first;
        } else {
          vendorModel.value.photo = null;
        }

        vendorModel.value.deliveryCharge = deliveryChargeModel;
        vendorModel.value.title = restaurantNameController.value.text;
        vendorModel.value.zoneId = selectedZone.value.id;
        vendorModel.value.isSelfDelivery = isSelfDelivery.value;
        vendorModel.value.packagingCharge = packagingChargeAmountController.value.text.isNotEmpty ? packagingChargeAmountController.value.text : '0';

        if (selectedSectionModel.value.adminCommision?.isEnabled == true || Constant.isSubscriptionModelApplied == true) {
          vendorModel.value.subscriptionPlanId = userModel.value.subscriptionPlanId;
          vendorModel.value.subscriptionPlan = userModel.value.subscriptionPlan;
          vendorModel.value.subscriptionExpiryDate = userModel.value.subscriptionExpiryDate;
          vendorModel.value.subscriptionTotalOrders = userModel.value.subscriptionPlan?.orderLimit;
        }

        if (Constant.userModel!.vendorID?.isNotEmpty == true) {
          await FireStoreUtils.updateVendor(vendorModel.value).then((value) {
            ShowToastDialog.closeLoader();
            ShowToastDialog.showToast("Store details save successfully".tr);
          });
        } else {
          vendorModel.value.adminCommission = selectedSectionModel.value.adminCommision;
          vendorModel.value.workingHours = [
            WorkingHours(
              day: 'Monday',
              timeslot: [Timeslot(from: '00:00', to: '23:59')],
            ),
            WorkingHours(
              day: 'Tuesday',
              timeslot: [Timeslot(from: '00:00', to: '23:59')],
            ),
            WorkingHours(
              day: 'Wednesday',
              timeslot: [Timeslot(from: '00:00', to: '23:59')],
            ),
            WorkingHours(
              day: 'Thursday',
              timeslot: [Timeslot(from: '00:00', to: '23:59')],
            ),
            WorkingHours(
              day: 'Friday',
              timeslot: [Timeslot(from: '00:00', to: '23:59')],
            ),
            WorkingHours(
              day: 'Saturday',
              timeslot: [Timeslot(from: '00:00', to: '23:59')],
            ),
            WorkingHours(
              day: 'Sunday',
              timeslot: [Timeslot(from: '00:00', to: '23:59')],
            ),
          ];
          if (vendorModel.value.latitude != null && vendorModel.value.longitude != null) {
            await FireStoreUtils.getTaxList(double.parse("${vendorModel.value.latitude}"), double.parse("${vendorModel.value.longitude}"), vendorModel.value.sectionId.toString()).then((value) {
              if (value == null) return;
              Constant.taxProductList = value.where((TaxModel taxModel) => taxModel.scope == "product").toList();
            });
          }
          await FireStoreUtils.firebaseCreateNewVendor(vendorModel.value).then((value) {
            ShowToastDialog.closeLoader();
            ShowToastDialog.showToast("Store details save successfully".tr);
          });
        }
        } catch (e) {
          debugPrint('AddRestaurantController.saveDetails failed: $e');
          ShowToastDialog.closeLoader();
          ShowToastDialog.showToast("Could not save store details. Please check your internet connection and try again.".tr);
        }
      } else {
        ShowToastDialog.showToast("The chosen area is outside the selected zone.".tr);
      }
    }
  }

  Map<String, dynamic> filters = {};

  void filter() {
    if (selectedService.contains('Good for Breakfast')) {
      filters['Good for Breakfast'] = 'Yes';
    } else {
      filters['Good for Breakfast'] = 'No';
    }
    if (selectedService.contains('Good for Lunch')) {
      filters['Good for Lunch'] = 'Yes';
    } else {
      filters['Good for Lunch'] = 'No';
    }

    if (selectedService.contains('Good for Dinner')) {
      filters['Good for Dinner'] = 'Yes';
    } else {
      filters['Good for Dinner'] = 'No';
    }

    if (selectedService.contains('Takes Reservations')) {
      filters['Takes Reservations'] = 'Yes';
    } else {
      filters['Takes Reservations'] = 'No';
    }

    if (selectedService.contains('Vegetarian Friendly')) {
      filters['Vegetarian Friendly'] = 'Yes';
    } else {
      filters['Vegetarian Friendly'] = 'No';
    }

    if (selectedService.contains('Live Music')) {
      filters['Live Music'] = 'Yes';
    } else {
      filters['Live Music'] = 'No';
    }

    if (selectedService.contains('Outdoor Seating')) {
      filters['Outdoor Seating'] = 'Yes';
    } else {
      filters['Outdoor Seating'] = 'No';
    }

    if (selectedService.contains('Free Wi-Fi')) {
      filters['Free Wi-Fi'] = 'Yes';
    } else {
      filters['Free Wi-Fi'] = 'No';
    }
  }

  final ImagePicker _imagePicker = ImagePicker();

  Future pickFile({required ImageSource source}) async {
    try {
      XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;
      images.add(image);
      Get.back();
    } on PlatformException catch (e) {
      ShowToastDialog.showToast("${"Failed to Pick :".tr} \n $e");
    }
  }
}
