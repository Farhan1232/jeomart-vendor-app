import 'package:get/get.dart';
import 'package:vendor/models/employee_role_model.dart';
import 'package:vendor/models/user_model.dart';
import 'package:vendor/utils/fire_store_utils.dart';

class EmployeeListController extends GetxController {
  @override
  void onInit() {
    getAllEmployeeList();
    super.onInit();
  }

  RxBool isLoading = true.obs;
  RxList<UserModel> employeeUserList = <UserModel>[].obs;

  /// One role read per role id for as long as this screen is open.
  ///
  /// Each employee row used to build a brand-new `getEmployeeRoleById` future
  /// every time the list rebuilt, so every rebuild re-read every visible role
  /// and flashed each row's badge back to a spinner.
  final Map<String, Future<EmployeeRoleModel?>> _roleReads = <String, Future<EmployeeRoleModel?>>{};

  Future<EmployeeRoleModel?> roleFor(String roleId) {
    return _roleReads.putIfAbsent(roleId, () => FireStoreUtils.getEmployeeRoleById(roleId));
  }

  Future<void> getAllEmployeeList() async {
    _roleReads.clear();
    await FireStoreUtils.getAllEmployee().then(
      (value) {
        if (value.isNotEmpty == true) {
          employeeUserList.value = value;
        }
      },
    );
    isLoading.value = false;
  }

  Future<void> updateEmployee(UserModel user) async {
    await FireStoreUtils.updateDriverUser(user);
  }
}
