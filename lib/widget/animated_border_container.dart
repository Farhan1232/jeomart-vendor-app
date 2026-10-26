import 'package:flutter/material.dart';
import 'package:vendor/themes/app_them_data.dart';
import 'package:vendor/widget/dimensions.dart';

class AnimatedBorderContainer extends StatefulWidget {
  final Widget child;
  final bool isLoading;
  final EdgeInsets? padding;
  final Color? color;
  const AnimatedBorderContainer({super.key, required this.child, required this.isLoading, this.padding, this.color});

  @override
  State<AnimatedBorderContainer> createState() => _AnimatedBorderContainerState();
}

class _AnimatedBorderContainerState extends State<AnimatedBorderContainer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    if (widget.isLoading) _controller.repeat();
  }

  /// The rotation is only drawn while [AnimatedBorderContainer.isLoading] is
  /// true - otherwise the gradient is null and the border is 0 wide. It used to
  /// spin regardless, so the Add/Edit Product form (five of these, none of them
  /// loading until an AI fill is requested) rebuilt them on every display frame
  /// for as long as it was open, typing and scrolling included.
  @override
  void didUpdateWidget(covariant AnimatedBorderContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isLoading && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
            border: Border.all(width: widget.isLoading ? 2 : 0, color: Colors.transparent),
            gradient: widget.isLoading ? SweepGradient(
              startAngle: 0.0,
              endAngle: 6.28,
              colors: [
                Colors.red,
                Colors.green,
                Colors.red,
                Colors.green,
                Colors.red,
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              transform: GradientRotation(_controller.value * 6.28),
            ) : null,
          ),
          child: Container(
            padding: widget.padding ?? const EdgeInsets.all(Dimensions.paddingSizeSmall),
            decoration: BoxDecoration(
              color: widget.color ?? AppThemeData.grey50,
              borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}