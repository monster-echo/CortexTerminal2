/// 相对时间的人类可读表示（中文文案，项目当前 UI 语言约定）。
/// 规则：刚内 → 「刚刚」；<1h → 「N 分钟前」；<24h → 「N 小时前」；
/// <7d → 「N 天前」；同年 → 「M月d日」；跨年 → 「yyyy年M月d日」。
String relativeTime(DateTime utcTime, {DateTime? now}) {
  final local = utcTime.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final diff = ref.difference(local);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  final sameYear = local.year == ref.year;
  return sameYear ? '${local.month}月${local.day}日' : '${local.year}年${local.month}月${local.day}日';
}
