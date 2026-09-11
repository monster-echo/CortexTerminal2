/// 内置法律文档（隐私政策 / 用户协议），参考 loficompanion 的结构化方案：
/// TS 对象 → Dart 常量，原生渲染（无 WebView / Markdown），中文为准、英文为对照译本。
///
/// ⚠️ 文案为初稿（基于当前架构事实：JWT 登录、网关中转终端数据、scrollback 快照 ≤512KB、
/// Worker 上报系统信息）。上架前需由运营/法务复核替换正式文本并更新 effectiveDate。
library;

class LegalSection {
  const LegalSection(this.title, this.paragraphs, {this.bullets = const []});

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
}

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.effectiveDate,
    required this.sections,
  });

  final String title;
  final String effectiveDate;
  final List<LegalSection> sections;
}

const zhPrivacyPolicy = LegalDocument(
  title: '隐私政策',
  effectiveDate: '2026-09-10',
  sections: [
    LegalSection('引言', [
      'Corterm（下称"本应用"）是一款远程终端与 AI Agent 工作区客户端。我们深知个人信息对你的重要性，并会按照法律法规要求，采取相应安全保护措施，尽力保护你的个人信息安全可控。在使用本应用前，请仔细阅读并充分理解本政策。',
    ]),
    LegalSection('我们收集的信息', [
      '为提供远程会话服务，我们会收集以下信息：',
    ], bullets: [
      '账号信息：注册用户名、密码（服务端以哈希形式存储）、手机号（如使用手机号登录）；',
      '账号头像（如你主动上传）；',
      '设备与连接信息：设备型号、操作系统版本、应用版本、网络状态、连接延迟统计；',
      '会话数据：你创建的终端会话元数据（名称、创建时间、所在 Worker）；',
      '终端内容：你在会话中的输入与输出会经由网关加密传输。为支持断线恢复，网关会在服务器上暂存最近不超过 512 KB 的终端滚动缓冲快照；',
      'Worker 信息：你自行接入的 Worker 设备的主机名、操作系统、架构与在线状态。',
    ]),
    LegalSection('我们如何使用信息', [
      '上述信息仅用于：身份验证与会话恢复、建立并维持你与自有 Worker 之间的远程连接、排查连接故障、以及向你展示会话列表与连接状态。我们不会将你的终端内容用于任何分析、训练或商业目的。',
    ]),
    LegalSection('信息的存储', [
      '终端滚动缓冲快照保存在网关服务器内存/数据库中，仅用于断线重连时恢复会话视图，你可以通过终止会话随时使其删除。登录凭据（JWT）仅保存在本设备的系统安全存储（iOS Keychain / Android Keystore）中；主题、语言、最近会话等偏好仅保存在本设备本地。',
    ]),
    LegalSection('信息的共享', [
      '我们不会向任何第三方出售你的个人信息。除为提供基础网络传输所必需（如你的设备与你自有 Worker 之间的通信）或依据法律法规、司法机关的强制性要求外，我们不会向第三方共享你的个人信息。',
    ]),
    LegalSection('你的权利', [
      '你可以：在设置中修改密码；随时终止并删除会话；上传或更换头像；注销账号。注销账号后，我们将删除与该账号关联的账号信息、会话记录与偏好数据，无法恢复。',
    ]),
    LegalSection('未成年人保护', [
      '本应用面向开发者的专业工具场景，不面向未成年人提供服务。',
    ]),
    LegalSection('政策更新', [
      '我们可能适时修订本政策。重大变更时，我们会在应用内显著位置进行提示。请定期查阅本政策以了解最新内容。',
    ]),
    LegalSection('联系我们', [
      '如对本政策有任何疑问、意见或建议，可通过应用内"帮助与反馈"或官方支持渠道与我们联系，我们将在 15 个工作日内回复。',
    ]),
  ],
);

const zhTermsOfService = LegalDocument(
  title: '用户协议',
  effectiveDate: '2026-09-10',
  sections: [
    LegalSection('协议范围', [
      '本协议是你与本应用开发者之间关于使用 Corterm 应用及配套远程会话服务的约定。你安装、登录或使用本应用，即表示已阅读并同意本协议。',
    ]),
    LegalSection('账号与安全', [
      '你应妥善保管账号与密码，并对账号下的全部操作负责。请勿将账号用于违法违规用途，或将本应用用于攻击、入侵、扫描任何未经授权的系统。',
    ]),
    LegalSection('服务说明', [
      '本应用提供远程终端的接入与管理能力。远程会话运行在你自行接入的 Worker 设备上；终端内容经网关中转传输。Worker 与网络条件由你自行提供和维护，我们不承诺特定的会话可用性。',
    ]),
    LegalSection('使用规范', [
      '使用本应用时，你承诺不：利用本应用从事危害网络安全的行为；干扰或破坏服务的正常运行；绕过或试图绕过任何安全机制；将服务用于任何法律禁止的目的。',
    ]),
    LegalSection('知识产权', [
      '本应用软件的著作权、商标权等知识产权归开发者所有。你在会话中产生的数据与内容的权利归你所有。',
    ]),
    LegalSection('责任限制', [
      '因不可抗力、网络故障、你自有设备或第三方服务故障导致的服务中断或数据损失，开发者在法律允许的最大范围内不承担责任。',
    ]),
    LegalSection('协议终止', [
      '你可以随时停止使用本应用并注销账号。若你严重违反本协议，我们有权暂停或终止向你提供服务。',
    ]),
    LegalSection('其他', [
      '本协议适用中华人民共和国法律。本协议任何条款被认定无效的，不影响其余条款的效力。',
    ]),
  ],
);

const enPrivacyPolicy = LegalDocument(
  title: 'Privacy Policy',
  effectiveDate: '2026-09-10',
  sections: [
    LegalSection('Introduction', [
      'Corterm (the "App") is a client for remote terminals and AI agent workspaces. We take the protection of your personal information seriously and apply appropriate security measures to keep it safe. Please read this policy carefully before using the App.',
    ]),
    LegalSection('Information We Collect', [
      'To provide remote session services, we collect:',
    ], bullets: [
      'Account information: username, password (stored server-side as a hash), phone number (if you sign in with a phone number), and avatar you choose to upload;',
      'Device and connection information: device model, OS version, app version, network status, and latency statistics;',
      'Session metadata: terminal sessions you create (name, creation time, hosting worker);',
      'Terminal content: your session input and output are relayed through the gateway. To support reconnects, the gateway keeps a rolling scrollback snapshot of at most 512 KB per session;',
      'Worker information: hostname, operating system, architecture and online status of workers you connect yourself.',
    ]),
    LegalSection('How We Use Information', [
      'The information above is used only for authentication and session recovery, establishing and maintaining connections between your devices and your own workers, troubleshooting connectivity, and presenting your session list and connection status. We never use your terminal content for analytics, model training, or commercial purposes.',
    ]),
    LegalSection('Storage', [
      'Scrollback snapshots are kept in gateway memory/database solely to restore your session view on reconnect, and are removed when you terminate the session. Your credentials (JWT) are stored only in the system secure storage on your device (iOS Keychain / Android Keystore). Preferences such as theme, language and recent sessions stay on your device.',
    ]),
    LegalSection('Sharing', [
      'We do not sell your personal information. Except for transmission that is strictly necessary to provide the service (communication between your devices and your own workers), or where required by applicable law or a competent authority, we do not share your personal information with third parties.',
    ]),
    LegalSection('Your Rights', [
      'You may change your password in Settings; terminate and delete sessions at any time; upload or change your avatar; and delete your account. When you delete your account, associated account information, session records and preference data are deleted and cannot be recovered.',
    ]),
    LegalSection('Minors', [
      'The App is a professional developer tool and is not directed at minors.',
    ]),
    LegalSection('Changes to This Policy', [
      'We may revise this policy from time to time. Material changes will be announced prominently within the App. Please review this policy periodically.',
    ]),
    LegalSection('Contact Us', [
      'If you have questions about this policy, contact us via in-app feedback or our official support channels. We aim to respond within 15 business days.',
    ]),
  ],
);

const enTermsOfService = LegalDocument(
  title: 'Terms of Service',
  effectiveDate: '2026-09-10',
  sections: [
    LegalSection('Scope', [
      'These terms govern your use of the Corterm App and its remote session services. Installing, signing in to, or using the App means you have read and accepted these terms.',
    ]),
    LegalSection('Account and Security', [
      'Keep your credentials safe; you are responsible for all actions under your account. Do not use the App for any unlawful purpose, or to attack, intrude into, or scan any system you are not authorized to access.',
    ]),
    LegalSection('The Service', [
      'The App provides access to and management of remote terminals. Sessions run on worker devices that you connect yourself; terminal content is relayed through the gateway. You provide and maintain your own workers and network conditions; no specific session availability is promised.',
    ]),
    LegalSection('Acceptable Use', [
      'You agree not to: use the App in ways that harm network security; interfere with or disrupt the service; bypass or attempt to bypass any security mechanism; or use the service for any purpose prohibited by law.',
    ]),
    LegalSection('Intellectual Property', [
      "The App's software is owned by its developers and protected by copyright and trademark law. Content and data you produce in your sessions remain yours.",
    ]),
    LegalSection('Limitation of Liability', [
      'To the maximum extent permitted by law, the developers are not liable for service interruptions or data loss caused by force majeure, network failures, or faults in your own devices or third-party services.',
    ]),
    LegalSection('Termination', [
      'You may stop using the App and delete your account at any time. If you seriously breach these terms, we may suspend or terminate the service to you.',
    ]),
    LegalSection('Miscellaneous', [
      'If any provision of these terms is held invalid, the remaining provisions stay in effect.',
    ]),
  ],
);
