import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:vendor/constant/collection_name.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/constant/show_toast_dialog.dart';
import 'package:vendor/models/payment_model/flutter_wave_model.dart';
import 'package:vendor/models/payment_model/paypal_model.dart';
import 'package:vendor/models/payment_model/razorpay_model.dart';
import 'package:vendor/models/payment_model/stripe_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/models/wallet_transaction_model.dart';
import 'package:vendor/models/withdraw_method_model.dart';
import 'package:vendor/models/withdrawal_model.dart';
import 'package:vendor/utils/fire_store_utils.dart';
import 'package:vendor/utils/firestore_paginator.dart';

class WalletController extends GetxController {
  RxBool isLoading = true.obs;

  Rx<TextEditingController> amountTextFieldController = TextEditingController().obs;
  Rx<TextEditingController> noteTextFieldController = TextEditingController().obs;

  Rx<UserModel> userModel = UserModel().obs;
  RxList<WalletTransactionModel> walletTransactionList = <WalletTransactionModel>[].obs;
  RxList<WithdrawalModel> withdrawalList = <WithdrawalModel>[].obs;

  RxInt selectedTabIndex = 0.obs;
  RxInt selectedValue = 0.obs;

  Rx<WithdrawMethodModel> withdrawMethodModel = WithdrawMethodModel().obs;

  Rx<RazorPayModel> razorPayModel = RazorPayModel().obs;
  Rx<PayPalModel> paypalDataModel = PayPalModel().obs;
  Rx<StripeModel> stripeSettingData = StripeModel().obs;
  Rx<FlutterWaveModel> flutterWaveSettingData = FlutterWaveModel().obs;

  @override
  void onInit() {
    // TODO: implement onInit
    getWalletTransaction(false);

    super.onInit();
  }

  Future<void> createAndSavePdf() async {
    // Create a new PDF document
    final PdfDocument document = PdfDocument();

    // Add a page to the document
    final PdfPage page = document.pages.add();

    // Create a PDF grid (table)
    final PdfGrid grid = PdfGrid();

    // Add columns to the grid
    grid.columns.add(count: 4);

    // Add headers to the grid
    grid.headers.add(1);
    final PdfGridRow header = grid.headers[0];
    header.cells[0].value = 'Description';
    header.cells[1].value = 'Order Id';
    header.cells[2].value = 'Amount';
    header.cells[3].value = 'Date';

    // Add rows to the grid
    PdfGridRow row = grid.rows.add();
    for (var element in walletTransactionList) {
      row.cells[0].value = element.note.toString();
      row.cells[1].value = Constant.orderId(orderId: element.orderId.toString());
      row.cells[2].value = Constant.amountShow(amount: element.amount.toString());
      row.cells[3].value = Constant.timestampToDateTime(element.date!);
      row = grid.rows.add();
    }

    // Draw the grid on the page
    grid.draw(page: page, bounds: const Rect.fromLTWH(0, 0, 0, 0));

    // Save the document
    final List<int> bytes = document.saveSync();

    // Dispose of the document
    document.dispose();

    // Get the application directory
    final Directory downloadsDirectory = Directory('/storage/emulated/0/Download');
    final String path = '${downloadsDirectory.path}/statement.pdf';
    final File file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    ShowToastDialog.showToast("Statement downloaded in download folder".tr);
    print('PDF saved at: $path');
  }

  RxDouble orderAmount = 0.0.obs;
  RxDouble taxAmount = 0.0.obs;

  Rx<DateTime> startDate = DateTime.now().subtract(const Duration(days: 1)).obs;
  Rx<DateTime> endDate = DateTime.now().obs;

  /// Withdrawal history is paged; see the note inside
  /// [getWalletTransaction] for why the transaction list is not.
  FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, WithdrawalModel>? withdrawalsPaginator;

  /// Keeps the derived lists in sync with the loaded pages.
  Worker? _paginatorWorker;

  bool get hasMoreWithdrawals => withdrawalsPaginator?.hasMore.value ?? false;

  Future<void> loadMoreWithdrawals() async {
    await withdrawalsPaginator?.loadMore();
  }

  Future<void> refreshWithdrawals() async {
    await withdrawalsPaginator?.refresh();
  }

  @override
  void onClose() {
    _paginatorWorker?.dispose();
    _paginatorWorker = null;
    withdrawalsPaginator?.dispose();
    withdrawalsPaginator = null;
    super.onClose();
  }

  /// Loads the Wallet tab.
  ///
  /// The transaction history, the first page of withdrawals, the payout
  /// settings and the withdraw method are independent reads. They used to be
  /// made strictly one after another - eight round trips in a row before the
  /// tab showed anything, again on every visit and after every filter. They are
  /// now started together and the tab waits for the slowest. Each still fills
  /// only its own fields, and the tab still waits for all of them.
  Future<void> getWalletTransaction(bool isFilter) async {
    await Future.wait<void>([
      _loadTransactions(isFilter),
      // The withdrawals query and the withdraw method both read the signed-in
      // store from `Constant.userModel`, so they start once [_loadUser] has made
      // sure that is the signed-in vendor - immediately, in the normal case.
      _loadUser().then<void>((_) async {
        await Future.wait<void>([_loadWithdrawals(), getPaymentMethod()]);
      }),
    ]);
    isLoading.value = false;
  }

  Future<void> _loadTransactions(bool isFilter) async {
    if (isFilter) {
      await FireStoreUtils.getFilterWalletTransaction(
        Timestamp.fromDate(DateTime(startDate.value.year, startDate.value.month, startDate.value.day, 00, 00)),
        Timestamp.fromDate(DateTime(endDate.value.year, endDate.value.month, endDate.value.day, 23, 59)),
      ).then((value) {
        if (value != null) {
          taxAmount.value = 0;
          orderAmount.value = 0;
          walletTransactionList.value = value;

          walletTransactionList.where((element) => element.paymentMethod == "tax").toList();
          for (var element in walletTransactionList) {
            if (element.orderId != null) {
              if (element.paymentMethod == "tax") {
                if (element.isTopup == false) {
                  taxAmount.value -= double.parse(element.amount.toString());
                } else {
                  taxAmount.value += double.parse(element.amount.toString());
                }
              } else {
                if (element.isTopup == false) {
                  orderAmount.value -= double.parse(element.amount.toString());
                } else {
                  orderAmount.value += double.parse(element.amount.toString());
                }
              }
            }
          }
        }
      });
    } else {
      await FireStoreUtils.getWalletTransaction().then((value) {
        if (value != null) {
          taxAmount.value = 0;
          orderAmount.value = 0;
          walletTransactionList.value = value;

          walletTransactionList.where((element) => element.paymentMethod == "tax").toList();
          for (var element in walletTransactionList) {
            if (element.orderId != null) {
              if (element.paymentMethod == "tax") {
                if (element.isTopup == false) {
                  taxAmount.value -= double.parse(element.amount.toString());
                } else {
                  taxAmount.value += double.parse(element.amount.toString());
                }
              } else {
                if (element.isTopup == false) {
                  orderAmount.value -= double.parse(element.amount.toString());
                } else {
                  orderAmount.value += double.parse(element.amount.toString());
                }
              }
            }
          }
        }
      });
    }

    // NOTE: the transaction fetch above is deliberately NOT paginated. This
    // screen shows running `orderAmount` / `taxAmount` totals derived from the
    // whole history, so paging it would display wrong money. Making it
    // paginated needs a server-side aggregate for those two figures.
    //
    // The withdrawal list has no such totals, so it pages normally.
  }

  Future<void> _loadWithdrawals() async {
    withdrawalsPaginator?.dispose();
    final paginator = FirestorePaginator<DocumentSnapshot<Map<String, dynamic>>, WithdrawalModel>(
      source: FirestorePageSource(FireStoreUtils.withdrawHistoryQuery()),
      mapper: (doc) {
        final data = doc.data();
        if (data == null) return null;
        try {
          return WithdrawalModel.fromJson(data);
        } catch (_) {
          return null;
        }
      },
      pageSize: 20,
    );
    withdrawalsPaginator = paginator;
    _paginatorWorker?.dispose();
    _paginatorWorker = ever<List<WithdrawalModel>>(paginator.items, (items) {
      withdrawalList.value = items;
    });
    await paginator.refresh();
  }

  Future<void> _loadUser() async {
    // The signed-in vendor's own document is usually already loaded; reuse it
    // instead of reading it again every time the wallet opens - but only when it
    // really is the signed-in vendor. `getUserProfile()` also assigns
    // `Constant.userModel`, and the order chat and the restaurant inbox call it
    // with the *customer's* id, so after opening a chat the reused profile was
    // the customer's: the wallet showed the customer's balance, checked a
    // withdrawal against it, and looked up the wrong withdrawals. In that case
    // the profile is read, as the wallet did before Session 1 - and that read
    // also puts the vendor back into `Constant.userModel`.
    final cachedUser = Constant.userModel;
    if (cachedUser != null && cachedUser.id == FireStoreUtils.getCurrentUid()) {
      userModel.value = cachedUser;
    } else {
      await FireStoreUtils.getUserProfile(FireStoreUtils.getCurrentUid()).then((value) {
        if (value != null) {
          userModel.value = value;
        }
      });
    }
  }

  /// The four payout gateway documents and the withdraw method - five
  /// independent reads, made together instead of one after another.
  Future<void> getPaymentMethod() async {
    await Future.wait<void>([
      FireStoreUtils.fireStore.collection(CollectionName.settings).doc("razorpaySettings").get().then((user) {
        try {
          razorPayModel.value = RazorPayModel.fromJson(user.data() ?? {});
        } catch (e) {
          debugPrint('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
        }
      }),
      FireStoreUtils.fireStore.collection(CollectionName.settings).doc("paypalSettings").get().then((paypalData) {
        try {
          paypalDataModel.value = PayPalModel.fromJson(paypalData.data() ?? {});
        } catch (error) {
          debugPrint(error.toString());
        }
      }),
      FireStoreUtils.fireStore.collection(CollectionName.settings).doc("stripeSettings").get().then((paypalData) {
        try {
          stripeSettingData.value = StripeModel.fromJson(paypalData.data() ?? {});
        } catch (error) {
          debugPrint(error.toString());
        }
      }),
      FireStoreUtils.fireStore.collection(CollectionName.settings).doc("flutterWave").get().then((paypalData) {
        try {
          flutterWaveSettingData.value = FlutterWaveModel.fromJson(paypalData.data() ?? {});
        } catch (error) {
          debugPrint(error.toString());
        }
      }),
      FireStoreUtils.getWithdrawMethod().then((value) {
        if (value != null) {
          withdrawMethodModel.value = value;
        }
      }),
    ]);
  }
}
