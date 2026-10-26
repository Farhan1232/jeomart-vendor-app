import 'package:get/get.dart';
import 'package:vendor/models/order_model.dart';
import 'package:vendor/models/product_model.dart';
import 'package:vendor/models/rating_model.dart';
import 'package:vendor/models/review_attribute_model.dart';
import 'package:vendor/models/vendor_category_model.dart';
import 'package:vendor/utils/fire_store_utils.dart';

class ProductRatingViewController extends GetxController {
  RxBool isLoading = true.obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getArgument();
    super.onInit();
  }

  Rx<OrderModel> orderModel = OrderModel().obs;
  RxString productId = "".obs;
  Rx<RatingModel> ratingModel = RatingModel().obs;
  Rx<ProductModel> productModel = ProductModel().obs;
  Rx<VendorCategoryModel> vendorCategoryModel = VendorCategoryModel().obs;

  RxList<ReviewAttributeModel> reviewAttributeList = <ReviewAttributeModel>[].obs;

  Future<void> getArgument() async {
    dynamic argumentData = Get.arguments;
    if (argumentData != null) {
      orderModel.value = argumentData['orderModel'];
      productId.value = argumentData['productId'];

      print("Order ID: ${orderModel.value.id}, Product ID: ${productId.value}");
      // The review and the product are independent, so they are read together.
      // The category needs the product, and the attributes need the category,
      // so those still follow in order.
      final reviewRead = FireStoreUtils.getOrderReviewsByID(orderModel.value.id.toString(), productId.value);
      final productRead = FireStoreUtils.getProductById(productId.value.split('~').first);

      await reviewRead.then((value) {
        if (value != null) {
          ratingModel.value = value;
        }
      });

      await productRead.then((value) {
        if (value != null) {
          productModel.value = value;
        }
      });

      await FireStoreUtils.getVendorCategoryByCategoryId(productModel.value.categoryID.toString()).then((value) async {
        if (value != null) {
          vendorCategoryModel.value = value;
          // One read per attribute, all at once instead of one after another;
          // added in the category's own order, as before.
          final attributes = await Future.wait(vendorCategoryModel.value.reviewAttributes!.map((element) => FireStoreUtils.getVendorReviewAttribute(element)));
          for (var value in attributes) {
            reviewAttributeList.add(value!);
          }
        }
      });
    }

    isLoading.value = false;
  }
}
