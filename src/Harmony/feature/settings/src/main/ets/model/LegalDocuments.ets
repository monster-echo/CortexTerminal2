/** Bundled website legal copy. Source: Console/src/locales/{zh,en}.json. */
export class LegalSection {
  title: string
  paragraphs: string[]
  constructor(title: string, paragraphs: string[]) { this.title = title; this.paragraphs = paragraphs }
}
export class LegalDocument {
  title: string
  updated: string
  sections: LegalSection[]
  constructor(title: string, updated: string, sections: LegalSection[]) {
    this.title = title; this.updated = updated; this.sections = sections
  }
}

const zhTerms: LegalDocument = new LegalDocument("服务条款", "最后更新：2026-05-28", [
  new LegalSection("1. 服务描述", ["Corterm（云枢终端）是一款安全的远程终端客户端，允许用户通过加密通道连接到自己的远程服务器和工作站。"]),
  new LegalSection("2. 用户账户", ["使用本服务需要创建账户。您有责任保护您的账户凭证安全。您同意不对您的账户进行未经授权的分享或转让。"]),
  new LegalSection("3. 可接受使用", ["您同意不会将本服务用于任何非法目的或违反任何适用法律法规的活动。您对通过本服务执行的命令和操作负全部责任。"]),
  new LegalSection("4. 服务可用性", ["我们尽力保持服务的持续可用性，但不保证服务将不间断或无错误。我们保留在提前通知的情况下进行维护和更新的权利。"]),
  new LegalSection("5. 账户删除", ["您可以随时通过应用设置删除您的账户。详细信息请参阅我们的 账户删除政策 和 隐私政策。"]),
  new LegalSection("6. 免责声明", ["本服务按\"现状\"提供，不作任何明示或暗示的保证。对于因使用或无法使用本服务而导致的任何直接、间接、附带或后果性损害，我们不承担责任。"]),
  new LegalSection("7. 条款变更", ["我们保留随时更新这些条款的权利。重大变更将通过应用内通知或电子邮件通知您。继续使用本服务即表示您接受更新后的条款。"]),
  new LegalSection("8. 联系方式", ["如有疑问，请联系 rwecho@live.com"]),
])

const zhPrivacy: LegalDocument = new LegalDocument("隐私政策", "最后更新：2026-05-28", [
  new LegalSection("1. 信息收集", ["Corterm 是一款远程终端客户端应用。我们收集以下必要信息以提供服务：", "账户信息：当您通过第三方登录（Apple、GitHub、Google）或手机号/密码注册时，我们收集用户名、邮箱地址和第三方提供的唯一标识符。", "设备信息：用于激活 Worker 的设备标识。", "会话数据：您创建的终端会话的元数据（不包含终端内容）。"]),
  new LegalSection("2. 数据使用", ["您的信息仅用于：", "• 提供和改进服务", "• 身份验证和账户安全", "• 服务运营和技术支持"]),
  new LegalSection("3. 数据存储", ["您的数据存储在我们的安全服务器上。终端会话的实时数据通过加密通道传输，我们不会存储您的终端输入和输出内容。"]),
  new LegalSection("4. 第三方服务", ["我们使用以下第三方服务进行身份验证，它们有各自的隐私政策：", "• Apple Sign-In", "• GitHub OAuth", "• Google Sign-In"]),
  new LegalSection("5. 数据删除", ["您可以随时在应用设置中删除您的账户。账户删除后，您的个人信息将在 30 天内从我们的活跃数据库中移除。详情请参阅 账户删除说明。"]),
  new LegalSection("6. 联系我们", ["如有隐私相关问题，请发送邮件至 rwecho@live.com"]),
])

const zhDeletion: LegalDocument = new LegalDocument("账户删除说明", "最后更新：2026-05-28", [
  new LegalSection("如何删除账户", ["打开 Corterm 应用", "进入设置页面", "滚动到底部，点击「注销账户」按钮", "阅读确认提示，点击「注销」", "在第二次确认中再次点击「注销」", "账户删除完成后，您将自动返回登录页面"]),
  new LegalSection("删除后的影响", ["注意：此操作不可逆。账户删除后您将无法恢复。", "账户删除后，以下数据将被处理：", "立即删除: 所有终端会话记录", "立即解除: 与 Worker 的绑定关系", "立即撤销: Apple ID 登录关联（如适用）", "标记为已删除: 您的账户信息将被标记为 \"deleted\" 状态"]),
  new LegalSection("删除后保留的数据", ["出于安全和审计目的，以下信息可能在有限时间内保留：", "审计日志（不含个人身份信息）"]),
  new LegalSection("删除后的账户状态", ["账户删除后，您将无法使用该账户登录。关联的第三方登录（Apple、GitHub、Google）授权将被解除。如需重新使用服务，您需要创建新账户。"]),
  new LegalSection("需要帮助？", ["如果您在删除账户过程中遇到问题，请联系 rwecho@live.com"]),
])

const enTerms: LegalDocument = new LegalDocument("Terms of Service", "Last updated: 2026-05-28", [
  new LegalSection("1. Service Description", ["Corterm is a secure remote terminal client that allows users to connect to their own remote servers and workstations through encrypted channels."]),
  new LegalSection("2. User Accounts", ["Using this service requires creating an account. You are responsible for keeping your account credentials secure. You agree not to share or transfer your account without authorization."]),
  new LegalSection("3. Acceptable Use", ["You agree not to use this service for any illegal purposes or activities that violate applicable laws and regulations. You are solely responsible for the commands and operations executed through this service."]),
  new LegalSection("4. Service Availability", ["We strive to maintain continuous service availability but do not guarantee uninterrupted or error-free service. We reserve the right to perform maintenance and updates with prior notice."]),
  new LegalSection("5. Account Deletion", ["You can delete your account at any time through the app settings. For details, please refer to our Account Deletion Policy and Privacy Policy."]),
  new LegalSection("6. Disclaimer", ["This service is provided \"as is\" without any express or implied warranties. We are not liable for any direct, indirect, incidental, or consequential damages arising from the use or inability to use this service."]),
  new LegalSection("7. Changes to Terms", ["We reserve the right to update these terms at any time. Significant changes will be notified through in-app notifications or email. Continued use of the service constitutes acceptance of the updated terms."]),
  new LegalSection("8. Contact", ["For questions, please contact rwecho@live.com"]),
])

const enPrivacy: LegalDocument = new LegalDocument("Privacy Policy", "Last updated: 2026-05-28", [
  new LegalSection("1. Information Collection", ["Corterm is a remote terminal client application. We collect the following necessary information to provide our services:", "Account Information: When you register via third-party login (Apple, GitHub, Google) or phone number/password, we collect your username, email address, and the unique identifier provided by the third party.", "Device Information: Device identifiers used for activating Workers.", "Session Data: Metadata of the terminal sessions you create (terminal content is not included)."]),
  new LegalSection("2. Data Usage", ["Your information is only used for:", "• Providing and improving services", "• Authentication and account security", "• Service operations and technical support"]),
  new LegalSection("3. Data Storage", ["Your data is stored on our secure servers. Real-time terminal session data is transmitted through encrypted channels. We do not store your terminal input and output content."]),
  new LegalSection("4. Third-Party Services", ["We use the following third-party services for authentication, each with their own privacy policies:", "• Apple Sign-In", "• GitHub OAuth", "• Google Sign-In"]),
  new LegalSection("5. Data Deletion", ["You can delete your account at any time in the app settings. After account deletion, your personal information will be removed from our active database within 30 days. See our Account Deletion Policy for details."]),
  new LegalSection("6. Contact Us", ["For privacy-related questions, please email rwecho@live.com"]),
])

const enDeletion: LegalDocument = new LegalDocument("Account Deletion", "Last updated: 2026-05-28", [
  new LegalSection("How to Delete Your Account", ["Open the Corterm app", "Go to the Settings page", "Scroll to the bottom and tap \"Delete Account\"", "Read the confirmation prompt and tap \"Delete\"", "Tap \"Delete\" again in the second confirmation", "After deletion, you will be automatically returned to the login page"]),
  new LegalSection("Effects of Deletion", ["Note: This action is irreversible. You will not be able to recover your account after deletion.", "After account deletion, the following data will be processed:", "Immediately deleted: All terminal session records", "Immediately unbound: Worker bindings", "Immediately revoked: Apple ID login association (if applicable)", "Marked as deleted: Your account information will be marked as \"deleted\" status"]),
  new LegalSection("Data Retained After Deletion", ["The following information may be retained for a limited time for security and auditing purposes:", "Audit logs (excluding personally identifiable information)"]),
  new LegalSection("Account Status After Deletion", ["After deletion, you will not be able to log in with this account. Associated third-party login authorizations (Apple, GitHub, Google) will be revoked. To use the service again, you will need to create a new account."]),
  new LegalSection("Need Help?", ["If you encounter issues during account deletion, please contact rwecho@live.com"]),
])

export function getLegalDocument(kind: string, language: string): LegalDocument {
  if (kind === 'privacy') return language.startsWith('zh') ? zhPrivacy : enPrivacy
  if (kind === 'account-deletion') return language.startsWith('zh') ? zhDeletion : enDeletion
  return language.startsWith('zh') ? zhTerms : enTerms
}
