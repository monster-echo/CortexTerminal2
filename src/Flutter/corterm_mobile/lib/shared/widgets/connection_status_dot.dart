import 'package:flutter/material.dart';

/// Session 状态小圆点（§13）：green/yellow/red/gray，不做文字。
class ConnectionStatusDot extends StatelessWidget {
  const ConnectionStatusDot({
    super.key,
    required this.color,
    this.size = 9,
    this.pulse = false,
  });

  /// Green Running / Yellow Waiting·Reconnecting / Red Error / Gray Ended。
  const ConnectionStatusDot.running({super.key, this.size = 9, this.pulse = false})
      : color = const Color(0xFF22C55E);
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
