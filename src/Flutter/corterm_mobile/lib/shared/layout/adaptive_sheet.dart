import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Anchor presentations to the pane that opened them. DisplayFeatureSubScreen
/// uses the native fold regions bridged by AdaptiveWindow to keep the sheet on
/// that side of the fold. Content stays top-aligned with a bounded width/height.
Future<T?> showAdaptiveModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool? showDragHandle,
  Color? backgroundColor,
  ShapeBorder? shape,
  AnimationStyle? sheetAnimationStyle,
}) {
  final box = context.findRenderObject() as RenderBox;
  final anchor = box.localToGlobal(box.size.center(Offset.zero));
  return showModalBottomSheet<T>(
    context: context,
    anchorPoint: anchor,
    useRootNavigator: true,
    constraints: const BoxConstraints(maxWidth: 560),
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    backgroundColor: backgroundColor,
    shape: shape,
    sheetAnimationStyle: sheetAnimationStyle,
    builder: (sheetContext) => LayoutBuilder(
      builder: (sheetContext, constraints) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(constraints.maxWidth, 560),
          maxHeight: constraints.maxHeight * .9,
        ),
        child: SingleChildScrollView(child: builder(sheetContext)),
      ),
    ),
  );
}

Future<T?> showCortermDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final box = context.findRenderObject() as RenderBox;
  return showDialog<T>(
    context: context,
    anchorPoint: box.localToGlobal(box.size.center(Offset.zero)),
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}
