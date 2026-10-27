import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:foldable/foldable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ControlEdge { none, left, right }

@immutable
class WindowRegion {
  const WindowRegion({required this.frame, required this.isDivision});

  final Rect frame;
  final bool isDivision;

  @override
  bool operator ==(Object other) =>
      other is WindowRegion &&
      frame == other.frame &&
      isDivision == other.isDivision;

  @override
  int get hashCode => Object.hash(frame, isDivision);
}

/// Coordinates are relative to the Flutter view, in logical pixels. Region frames
/// already include the clearance requested by UIKit; do not add it a second time.
@immutable
class WindowLayout {
  const WindowLayout({
    this.size = Size.zero,
    this.safeArea = EdgeInsets.zero,
    this.regularWidth = false,
    this.controlEdge = ControlEdge.none,
    this.statusBottom = 0,
    this.regions = const [],
  });

  final Size size;
  final EdgeInsets safeArea;
  final bool regularWidth;
  final ControlEdge controlEdge;
  final double statusBottom;
  final List<WindowRegion> regions;

  @override
  bool operator ==(Object other) =>
      other is WindowLayout &&
      size == other.size &&
      safeArea == other.safeArea &&
      regularWidth == other.regularWidth &&
      controlEdge == other.controlEdge &&
      statusBottom == other.statusBottom &&
      listEquals(regions, other.regions);

  @override
  int get hashCode => Object.hash(
    size,
    safeArea,
    regularWidth,
    controlEdge,
    statusBottom,
    Object.hashAll(regions),
  );

  Rect? get verticalDivision => regions
      .where(
        (region) =>
            region.isDivision && region.frame.height > region.frame.width,
      )
      .map((region) => region.frame)
      .firstOrNull;

  WindowLayout forPane(Rect pane) {
    final includesLeft = pane.left == 0;
    final includesRight = pane.right >= size.width;
    return WindowLayout(
      size: pane.size,
      safeArea: EdgeInsets.fromLTRB(
        includesLeft ? safeArea.left : 0,
        safeArea.top,
        includesRight ? safeArea.right : 0,
        safeArea.bottom,
      ),
      regularWidth: regularWidth,
      controlEdge:
          controlEdge == ControlEdge.left && !includesLeft ||
              controlEdge == ControlEdge.right && !includesRight
          ? ControlEdge.none
          : controlEdge,
      statusBottom: statusBottom,
      regions: regions
          .where((region) => region.frame.overlaps(pane))
          .map(
            (region) => WindowRegion(
              frame: region.frame.intersect(pane).shift(-pane.topLeft),
              isDivision: region.isDivision,
            ),
          )
          .toList(growable: false),
    );
  }
}

class WindowLayoutScope extends InheritedWidget {
  const WindowLayoutScope({
    super.key,
    required this.layout,
    required super.child,
  });

  final WindowLayout layout;

  static WindowLayout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowLayoutScope>()?.layout ??
      const WindowLayout();

  @override
  bool updateShouldNotify(WindowLayoutScope oldWidget) =>
      layout != oldWidget.layout;
}

/// Share MV2's provider and fixed chrome. The fold remains a layout input;
/// publishing it to MediaQuery would confine every modal to half the display.
class AdaptiveWindow extends StatelessWidget {
  const AdaptiveWindow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FoldableProvider(
    child: AdaptiveToolbarHost(
      child: Builder(
        builder: (context) {
          final fold = DuoMediaQuery.of(context);
          final pose = DuoPoseScope.of(context);
          return WindowLayoutScope(
            layout: WindowLayout(
              size: MediaQuery.sizeOf(context),
              safeArea: MediaQuery.viewPaddingOf(context),
              regularWidth: fold.horizontalSizeClass == SizeClass.regular,
              controlEdge: pose == null
                  ? ControlEdge.none
                  : pose.onLeft
                  ? ControlEdge.left
                  : ControlEdge.right,
              regions: [
                for (final region in fold.regions.where(
                  (region) => region.isActive,
                ))
                  WindowRegion(
                    frame: region.bounds,
                    isDivision: region.kind == ReservedRegionKind.division,
                  ),
              ],
            ),
            child: child,
          );
        },
      ),
    ),
  );
}
