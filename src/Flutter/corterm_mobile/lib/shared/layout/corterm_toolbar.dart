import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as platform;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

String cortermSfSymbol(IconData icon) =>
    <IconData, String>{
      Icons.add: 'plus',
      Icons.add_rounded: 'plus',
      LucideIcons.plus: 'plus',
      Icons.refresh: 'arrow.clockwise',
      Icons.refresh_rounded: 'arrow.clockwise',
      LucideIcons.refreshCw: 'arrow.clockwise',
      Icons.search: 'magnifyingglass',
      Icons.search_rounded: 'magnifyingglass',
      LucideIcons.search: 'magnifyingglass',
      Icons.more_horiz: 'ellipsis',
      Icons.more_vert: 'ellipsis',
      Icons.more_horiz_rounded: 'ellipsis',
      Icons.keyboard: 'keyboard',
      Icons.keyboard_outlined: 'keyboard',
      Icons.keyboard_hide_outlined: 'keyboard.chevron.compact.down',
      Icons.folder_outlined: 'folder',
      Icons.folder_open: 'folder',
      LucideIcons.folder: 'folder',
      Icons.arrow_back: 'chevron.left',
      LucideIcons.arrowLeft: 'chevron.left',
      Icons.close: 'xmark',
      LucideIcons.x: 'xmark',
      Icons.settings_outlined: 'gearshape',
      LucideIcons.settings: 'gearshape',
      Icons.drive_file_move_outline: 'folder.badge.arrow.forward',
      Icons.create_new_folder_outlined: 'folder.badge.plus',
      Icons.link: 'link',
      Icons.restore_from_trash_outlined: 'arrow.uturn.backward',
      Icons.check: 'checkmark',
      Icons.copy: 'doc.on.doc',
      Icons.download_outlined: 'arrow.down.to.line',
      Icons.menu_open: 'sidebar.left',
      Icons.chevron_left: 'chevron.left',
      Icons.swap_horiz: 'arrow.left.arrow.right',
    }[icon] ??
    '';

String _text(Widget? widget) => switch (widget) {
  Text value => value.data ?? value.textSpan?.toPlainText() ?? '',
  Row value => value.children.map(_text).where((s) => s.isNotEmpty).join(' '),
  Padding value => _text(value.child),
  _ => '',
};
platform.AdaptiveAppBarAction cortermToolbarAction(
  BuildContext context,
  Widget widget,
) {
  if (widget is PopupMenuButton) {
    final entries = widget
        .itemBuilder(context)
        .whereType<PopupMenuItem>()
        .toList();
    final icon = widget.icon is Icon
        ? (widget.icon as Icon).icon
        : Icons.more_horiz;
    return platform.AdaptiveAppBarAction(
      iosSymbol: cortermSfSymbol(icon!).isEmpty
          ? 'ellipsis'
          : cortermSfSymbol(icon),
      icon: icon,
      label:
          widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
      menuItems: [
        for (final entry in entries)
          platform.AdaptivePopupMenuItem(
            label: _text(entry.child),
            value: entry.value,
            enabled: entry.enabled,
          ),
      ],
      onMenuItemSelected: (index, item) {
        if (!entries[index].enabled) return;
        entries[index].onTap?.call();
        // Keep the reified callback type: reading through PopupMenuButton<dynamic>
        // casts a String callback to ValueChanged<dynamic> and throws at runtime.
        final dynamic onSelected = (widget as dynamic).onSelected;
        onSelected?.call(entries[index].value);
      },
    );
  }
  final IconData? icon;
  final VoidCallback? onPressed;
  final String label;
  if (widget is IconButton) {
    icon = widget.icon is Icon ? (widget.icon as Icon).icon : null;
    onPressed = widget.onPressed;
    label = widget.tooltip ?? '';
  } else if (widget is ShadIconButton) {
    icon = widget.icon is Icon ? (widget.icon as Icon).icon : null;
    onPressed = widget.onPressed;
    label = '';
  } else if (widget is TextButton) {
    return platform.AdaptiveAppBarAction(
      title: _text(widget.child),
      label: _text(widget.child),
      onPressed: () => widget.onPressed?.call(),
      tintColor: widget.onPressed == null
          ? Theme.of(context).disabledColor
          : null,
    );
  } else {
    throw UnsupportedError(
      'Declare a semantic toolbar action for ${widget.runtimeType}',
    );
  }
  final symbol = icon == null ? '' : cortermSfSymbol(icon);
  return platform.AdaptiveAppBarAction(
    iosSymbol: symbol.isEmpty ? null : symbol,
    icon: icon,
    title: symbol.isEmpty ? label : null,
    iconWidget: icon == null && widget is IconButton ? widget.icon : null,
    label: label,
    onPressed: () => onPressed?.call(),
    tintColor: onPressed == null ? Theme.of(context).disabledColor : null,
  );
}

class CortermGlassButton extends StatelessWidget {
  const CortermGlassButton({
    super.key,
    required this.symbol,
    required this.label,
    required this.onPressed,
  });
  final String symbol;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: platform.IOS26GlassCapsule(
      items: [platform.GlassCapsuleItem(symbol: symbol, label: label)],
      onTap: (_) => onPressed(),
    ),
  );
}
