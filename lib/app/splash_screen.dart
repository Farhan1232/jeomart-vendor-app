import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vendor/controller/splash_controller.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SplashController>(
      init: SplashController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SizedBox.expand(
            child: Image.asset(
              'assets/images/vendor_splash.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
        );
      },
    );
  }
}
