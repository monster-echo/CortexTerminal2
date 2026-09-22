import 'package:flutter/material.dart';

/// Session 状态小圆点（§13）：颜色一律由调用方从主题状态色取（scheme.success 等）。
class ConnectionStatusDot extends StatelessWidget {
  const ConnectionStatusDot({
    super.key,
    required this.color,
    this.size = 9,
    this.pulse = false,
  });

  final Color color;
  final double size;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulse) return dot;
    return _PulsingDot(child: dot);
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.child});

  final Widget child;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_controller),
        child: widget.child,
      );
}
