// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'Corterm';

  @override
  String get cancel => '取消';

  @override
  String get ok => '确定';

  @override
  String get retry => '重试';

  @override
  String get delete => '注销';

  @override
  String get rename => '重命名';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get paste => '粘贴';

  @override
  String get save => '保存';

  @override
  String get unknown => '未知';

  @override
  String get loading => '加载中…';

  @override
  String get gatewayUrl => '网关地址';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get phoneNumber => '手机号';

  @override
  String get verificationCode => '验证码';

  @override
  String get sendCode => '发送验证码';

  @override
  String codeSentTo(String phone) {
    return '验证码已发送至 $phone';
  }

  @override
  String get passwordLogin => '密码登录';

  @override
  String get phoneLogin => '手机登录';

  @override
  String get signIn => '登录';

  @override
  String get signingIn => '登录中…';

  @override
  String get sendingCode => '发送中…';

  @override
  String get slideToVerify => '滑动验证';

  @override
  String get verifying => '验证中…';

  @override
  String phoneCodeResendIn(int seconds) {
    return '$seconds 秒后重发';
  }

  @override
  String get invalidGatewayUrl => '请输入有效的网关地址';

  @override
  String get invalidUsername => '请输入用户名';

  @override
  String get invalidPassword => '请输入密码';

  @override
  String get invalidPhone => '请输入有效的手机号';

  @override
  String get invalidCode => '请输入验证码';

  @override
  String get loginFailed => '登录失败';

  @override
  String get homeTitle => '首页';

  @override
  String get runningSessions => '运行中的会话';

  @override
  String get recentSessions => '最近会话';

  @override
  String get workers => 'Worker';

  @override
  String get newSession => '新建会话';

  @override
  String get noActiveSessions => '暂无活动会话';

  @override
  String get noActiveSessionsHint => '打开一个远程终端开始工作。';

  @override
  String get noWorkers => '没有已连接的 Worker';

  @override
  String get workerOffline => '离线';

  @override
  String get workerOnline => '在线';

  @override
  String get allSessions => '全部会话';

  @override
  String get noSessions => '还没有会话';

  @override
  String get sessionRenameTitle => '重命名会话';

  @override
  String get sessionNameLabel => '会话名称';

  @override
  String get terminateSession => '终止会话';

  @override
  String get deleteSession => '删除会话';

  @override
  String deleteSessionConfirmTitle(Object name) {
    return '删除 $name？';
  }

  @override
  String get deleteSessionConfirmBody => '将删除该会话记录。远程进程已停止。';

  @override
  String terminateConfirmTitle(Object name) {
    return '终止 $name？';
  }

  @override
  String get terminateConfirmBody => '将停止远程会话及其运行中的进程。';

  @override
  String get terminate => '终止';

  @override
  String get statusAttached => '运行中';

  @override
  String get statusDetachedGracePeriod => '运行中';

  @override
  String get statusRecovering => '恢复中';

  @override
  String get statusExited => '已结束';

  @override
  String get statusExpired => '已结束';

  @override
  String get groupActive => '活跃';

  @override
  String get groupEnded => '已结束';

  @override
  String get sessionDetails => '会话详情';

  @override
  String get sessionId => '会话 ID';

  @override
  String get agentKind => 'Agent';

  @override
  String get worker => 'Worker';

  @override
  String get createdAt => '创建时间';

  @override
  String get lastActivity => '最近活动';

  @override
  String get exitCode => '退出码';

  @override
  String get exitReason => '退出原因';

  @override
  String get sessions => '会话';

  @override
  String get current => '当前';

  @override
  String get selectSession => '选择会话';

  @override
  String get createSessionFailed => '创建会话失败';

  @override
  String get chooseWorker => '选择 Worker';

  @override
  String get runtimeTerminal => '终端';

  @override
  String get runtimeShell => 'Shell';

  @override
  String get runtimeShellHint =>
      '运行任意 CLI —— Claude Code、Codex 等 Agent 会被自动识别。';

  @override
  String get connection => '连接';

  @override
  String get connectionState => '状态';

  @override
  String get gateway => '网关';

  @override
  String get latency => '延迟';

  @override
  String get network => '网络';

  @override
  String get networkWifi => 'Wi-Fi';

  @override
  String get networkMobile => '移动网络';

  @override
  String get networkEthernet => '有线网络';

  @override
  String get networkNone => '无网络';

  @override
  String get connLive => '已连接';

  @override
  String get connConnecting => '连接中…';

  @override
  String get connReplaying => '恢复中…';

  @override
  String get connReconnecting => '重新连接中…';

  @override
  String get connClosed => '已断开';

  @override
  String get connExited => '已结束';

  @override
  String get connError => '错误';

  @override
  String get connIdle => '空闲';

  @override
  String get gatewayConnected => '已连接';

  @override
  String get gatewayDisconnected => '未连接';

  @override
  String ms(int n) {
    return '$n ms';
  }

  @override
  String get more => '更多';

  @override
  String get files => '文件';

  @override
  String get settings => '设置';

  @override
  String get reconnectBanner => '重新连接中…';

  @override
  String get connectBanner => '连接中…';

  @override
  String get restoringBanner => '正在恢复会话…';

  @override
  String sessionEndedBanner(String reason) {
    return '会话已结束（$reason）';
  }

  @override
  String get sessionErrorBanner => '连接错误';

  @override
  String get displacedBanner => '会话已在其他端打开 —— 点按重新连接';

  @override
  String get tapToReconnect => '点按重新连接';

  @override
  String get account => '账号';

  @override
  String get appearance => '外观';

  @override
  String get terminal => '终端';

  @override
  String get keyboardToolbar => '键盘工具栏';

  @override
  String get language => '语言';

  @override
  String get security => '安全';

  @override
  String get about => '关于';

  @override
  String get appearanceSystem => '跟随系统';

  @override
  String get appearanceLight => '浅色';

  @override
  String get appearanceDark => '深色';

  @override
  String get terminalFontSize => '字体大小';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '简体中文';

  @override
  String get changePassword => '修改密码';

  @override
  String get currentPassword => '当前密码';

  @override
  String get newPassword => '新密码';

  @override
  String get passwordChanged => '密码已修改';

  @override
  String get logout => '退出登录';

  @override
  String get logoutConfirm => '退出登录 Corterm？';

  @override
  String get appVersion => '版本';

  @override
  String get gatewayVersion => '网关版本';

  @override
  String fontSizeFmt(double pt) {
    return '$pt pt';
  }

  @override
  String get legal => '协议与政策';

  @override
  String legalVersionCaption(String date) {
    return '生效日期：$date';
  }

  @override
  String get legalIndexIntro => '以下文档约束你对 Corterm 的使用。中文版本为准，英文版本为对照译本。';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get privacyPolicyDesc => '我们收集哪些信息、如何使用与存储。';

  @override
  String get termsOfService => '用户协议';

  @override
  String get termsOfServiceDesc => '服务范围、使用规范与责任限制。';

  @override
  String get consentPrefix => '我已阅读并同意';

  @override
  String get consentAnd => '和';

  @override
  String get consentAlertTitle => '服务协议及隐私保护';

  @override
  String get consentAlertBody => '为了更好地保障您的合法权益，请阅读并同意《用户协议》与《隐私政策》。';

  @override
  String get agree => '同意';

  @override
  String get disagree => '不同意';

  @override
  String get deleteAccount => '注销账号';

  @override
  String get deleteAccountConfirmTitle => '注销该账号？';

  @override
  String get deleteAccountConfirmBody => '服务端将永久删除该账号、其会话记录与偏好数据，操作无法恢复。';

  @override
  String get aboutTagline => '移动端 AI Agent 工作区';

  @override
  String get filesTitle => '文件';

  @override
  String get upload => '上传';

  @override
  String get uploadDone => '上传完成';

  @override
  String get uploadFailed => '上传失败';

  @override
  String get downloadFailed => '下载失败';

  @override
  String get emptyFolder => '空目录';

  @override
  String get listTruncated => '列表已达服务器上限，已截断。';

  @override
  String get workersTitle => 'Worker';

  @override
  String sessionCount(int n) {
    return '$n 个会话';
  }

  @override
  String get workerHostname => '主机名';

  @override
  String get workerOs => '系统';

  @override
  String get workerVersion => 'Worker 版本';

  @override
  String get upgrade => '升级';

  @override
  String get upgradeConfirm => '立即升级该 Worker？';

  @override
  String get openSessions => '已打开的会话';

  @override
  String get diagnostics => '诊断';

  @override
  String get gatewayReachable => '网关可达性';

  @override
  String get diagnosticTesting => '检测中…';

  @override
  String get diagnosticFail => '不可达';

  @override
  String get platform => '设备';

  @override
  String get keepScreenAwake => '保持屏幕常亮';

  @override
  String get otherLoginMethods => '其他登录方式';

  @override
  String oauthPending(String provider) {
    return '等待 $provider 授权…';
  }

  @override
  String oauthFailed(String provider) {
    return '$provider 登录失败';
  }

  @override
  String get createSession => '创建会话';

  @override
  String get creating => '创建中…';

  @override
  String get selectWorker => '选择 Worker';

  @override
  String get create => '创建';
}
