import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as platform;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/theme/corterm_theme.dart';
import '../widgets/app_bar.dart';
import 'corterm_toolbar.dart';

/// Pages publish their commands to MV2's persistent toolbar host. The host
/// owns the side bar; the page owns only its title, actions and content.
class AdaptivePageScaffold extends StatefulWidget {
  const AdaptivePageScaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.resizeToAvoidBottomInset,
    this.toolbarActions,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final bool? resizeToAvoidBottomInset;
  final List<platform.AdaptiveAppBarAction>? toolbarActions;

  @override
  State<AdaptivePageScaffold> createState() => _AdaptivePageScaffoldState();
}

class _AdaptivePageScaffoldState extends State<AdaptivePageScaffold> {
  final _bodyKey = GlobalKey();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  platform.ToolbarRegistry? _registry;

  @override
  void dispose() {
    _registry?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = platform.ToolbarChromeScope.maybeOf(context);
    final route = ModalRoute.of(context);
    final hosted =
        chrome?.hostsToolbar == true && (route == null || route is PageRoute);
    final bar = switch (widget.appBar) {
      CortermAppBar value => value.build(context),
      AppBar value => value,
      _ => null,
    };
    final c = colorsOf(context);
    if (hosted) {
      final registry = platform.ToolbarRegistry.maybeOf(context)!;
      _registry = registry;
      final navigator = Navigator.maybeOf(context);
      final enclosing = <ModalRoute<Object?>>[];
      var outer = navigator?.context;
      while (outer != null) {
        final parent = ModalRoute.of(outer);
        if (parent == null) break;
        enclosing.add(parent);
        outer = outer.findAncestorStateOfType<NavigatorState>()?.context;
      }
      Widget? leading = bar?.leading;
      if (leading is BackButton) {
        final back = leading;
        leading = platform.DuoBarBackButton(
          onPressed: back.onPressed ?? () => navigator!.maybePop(),
        );
      } else if (leading is ShadIconButton && leading.onPressed != null) {
        final button = leading;
        leading = CortermGlassButton(
          symbol: cortermSfSymbol((button.icon as Icon).icon!),
          label: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: button.onPressed!,
        );
      } else if (leading is IconButton &&
          leading.onPressed != null &&
          leading.icon is Icon) {
        final button = leading;
        leading = CortermGlassButton(
          symbol: cortermSfSymbol((button.icon as Icon).icon!),
          label: button.tooltip ?? '',
          onPressed: button.onPressed!,
        );
      } else if (bar?.automaticallyImplyLeading == true &&
          widget.drawer != null) {
        leading = CortermGlassButton(
          symbol: 'line.3.horizontal',
          label: MaterialLocalizations.of(context).openAppDrawerTooltip,
          onPressed: () => _scaffoldKey.currentState!.openDrawer(),
        );
      }
      if (leading == null &&
          bar?.automaticallyImplyLeading == true &&
          navigator?.canPop() == true) {
        leading = platform.DuoBarBackButton(
          onPressed: () => navigator!.maybePop(),
        );
      }
      final title = bar?.title;
      final titleText = title is Text ? title.data : null;
      registry.upsert(
        platform.ToolbarEntry(
          id: this,
          appBar: bar == null
              ? null
              : platform.AdaptiveAppBar(
                  title: titleText,
                  titleWidget: titleText == null ? title : null,
                  leading: leading,
                  tintColor: c.textPrimary,
                  actions:
                      widget.toolbarActions ??
                      [
                        for (final action in bar.actions ?? const <Widget>[])
                          cortermToolbarAction(context, action),
                      ],
                ),
          titleOverlay: titleText == null && title != null
              ? Theme(
                  data: Theme.of(context),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                    child: Padding(
                      padding: chrome!.hostsDuoControls ? EdgeInsets.zero : EdgeInsets.only(
                        left: leading == null ? 16 : 76,
                        right: 16 + (bar?.actions?.length ?? 0) * 48.0,
                      ),
                      child: Material(type: MaterialType.transparency, child: title),
                    ),
                  ),
                )
              : null,
          route: route,
          navigator: navigator,
          enclosingRoutes: enclosing,
          visible:
              TickerMode.valuesOf(context).enabled && Visibility.of(context),
          shownInPlace: Visibility.of(context),
        ),
      );
    } else {
      _registry?.remove(this);
      _registry = null;
    }
    final topInset = !hosted || bar == null
        ? 0.0
        : chrome!.hostsDuoControls
        ? platform.kDuoTitleBandHeight
        : platform.kHostedToolbarHeight + MediaQuery.paddingOf(context).top;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: widget.backgroundColor,
      appBar: hosted ? null : widget.appBar,
      drawer: widget.drawer,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar: widget.bottomNavigationBar,
      body: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: SafeArea(
          top: !hosted && widget.appBar == null,
          child: Column(
            children: [
              if (hosted && bar?.bottom != null) bar!.bottom!,
              Expanded(
                child: KeyedSubtree(
                  key: _bodyKey,
                  child: widget.body ?? const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
