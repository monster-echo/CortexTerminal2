; 云枢终端 (Corterm Worker UI) Windows 安装脚本 — Inno Setup
; 用法: iscc.exe /DMyAppVersion=<version> worker-ui.iss
; 产物: release\云枢终端-<version>-setup.exe（拖拽安装的 .app 等价物，Windows 的标准安装向导）

#define MyAppName "云枢终端"
#define MyAppPublisher "Corterm"
#define MyAppExeName "worker_ui.exe"
#define MyAppId "{{30fbe01a-84c0-4955-aef2-fdf189343856}"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; 按用户安装（无需管理员，装到 %LOCALAPPDATA%\Programs），worker 本身也装在用户目录 ~/.corterm
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
OutputDir=release
; ASCII 文件名：中文在 gh release 上传时会丢字符；固定名不带版本号，
; 自更新通过 releases/latest/download/<asset> 直达（对应 self_updater.dart）。
OutputBaseFilename=corterm-ui-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
DisableProgramGroupPage=yes

[Languages]
; ChineseSimplified.isl 随仓库提交，choco 版 Inno Setup 不带官方语言包
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter 构建产物（exe + dll + flutter 资源，含内置 worker 二进制）
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; 不带 skipifsilent：自更新的静默覆盖安装完成后也要把应用重新拉起。
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall
