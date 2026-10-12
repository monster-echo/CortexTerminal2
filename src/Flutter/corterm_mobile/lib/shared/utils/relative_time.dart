/// Short relative time for session lists, following the selected app locale.
String relativeTime(
  DateTime utcTime, {
  DateTime? now,
  String languageCode = 'zh',
}) {
  final local = utcTime.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final diff = ref.difference(local);
  if (languageCode != 'zh') {
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return local.year == ref.year
        ? '${local.month}/${local.day}'
        : '${local.year}/${local.month}/${local.day}';
  }
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  final sameYear = local.year == ref.year;
  return sameYear
      ? '${local.month}月${local.day}日'
      : '${local.year}年${local.month}月${local.day}日';
}
