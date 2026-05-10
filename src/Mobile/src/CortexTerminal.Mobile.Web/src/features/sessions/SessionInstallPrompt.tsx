import { IonButton, IonIcon } from "@ionic/react";
import { checkmarkOutline, copyOutline, keyOutline } from "ionicons/icons";
import { useState } from "react";

const bashInstallCommand = "curl -fsSL https://gateway.ct.rwecho.top/install.sh | sh";
const psInstallCommand =
  'powershell -Command "irm https://gateway.ct.rwecho.top/install.ps1 | iex"';
const activateUrl = "https://gateway.ct.rwecho.top/activate";

async function copyToClipboard(text: string) {
  await navigator.clipboard?.writeText(text);
}

const termStyle: React.CSSProperties = {
  background: "#0d1117",
  borderRadius: 12,
  padding: 0,
  margin: "16px",
  overflow: "hidden",
  fontFamily: "'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace",
  fontSize: 13,
  lineHeight: 1.7,
};

const termHeaderStyle: React.CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: 6,
  padding: "10px 14px",
  background: "#161b22",
  borderBottom: "1px solid #21262d",
};

const dotStyle = (color: string): React.CSSProperties => ({
  width: 10,
  height: 10,
  borderRadius: 5,
  background: color,
  display: "inline-block",
});

const termBodyStyle: React.CSSProperties = {
  padding: "16px 14px",
  color: "#c9d1d9",
};

const promptStyle: React.CSSProperties = {
  color: "#58a6ff",
  userSelect: "none",
};

const commentStyle: React.CSSProperties = {
  color: "#8b949e",
};

const successStyle: React.CSSProperties = {
  color: "#3fb950",
};

const highlightStyle: React.CSSProperties = {
  color: "#ffa657",
};

const cmdStyle: React.CSSProperties = {
  color: "#c9d1d9",
  wordBreak: "break-all",
};

function CopyBtn({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <IonButton
      fill="clear"
      size="small"
      style={{ margin: 0, minHeight: 28 }}
      color={copied ? "success" : "medium"}
      onClick={() => {
        void copyToClipboard(text).then(() => {
          setCopied(true);
          setTimeout(() => setCopied(false), 2000);
        });
      }}
    >
      <IonIcon slot="icon-only" icon={copied ? checkmarkOutline : copyOutline} />
    </IonButton>
  );
}

interface TerminalBlockProps {
  title: string;
  children: React.ReactNode;
}

function TerminalBlock({ title, children }: TerminalBlockProps) {
  return (
    <div style={termStyle}>
      <div style={termHeaderStyle}>
        <span style={dotStyle("#ff5f57")} />
        <span style={dotStyle("#febc2e")} />
        <span style={dotStyle("#28c840")} />
        <span style={{ color: "#8b949e", fontSize: 12, marginLeft: 8 }}>{title}</span>
      </div>
      <div style={termBodyStyle}>{children}</div>
    </div>
  );
}

export default function SessionInstallPrompt() {
  return (
    <div style={{ paddingBottom: 24 }}>
      {/* Intro */}
      <TerminalBlock title="Corterm — Quick Start">
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}># 还没有可用的 Session</span>
        </div>
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}># Session 运行在 Worker 上，需要先在一台机器上安装 Worker</span>
        </div>
        <div>
          <span style={successStyle}>  按以下步骤操作，一分钟即可开始使用远程终端</span>
        </div>
      </TerminalBlock>

      {/* Step 1: Install macOS/Linux */}
      <TerminalBlock title="Step 1 — 安装 Worker (macOS / Linux)">
        <div style={{ marginBottom: 8, display: "flex", alignItems: "center" }}>
          <span style={promptStyle}>$ </span>
          <code style={cmdStyle}>{bashInstallCommand}</code>
          <CopyBtn text={bashInstallCommand} />
        </div>
      </TerminalBlock>

      {/* Step 1 alt: Windows */}
      <TerminalBlock title="Step 1 — 安装 Worker (Windows)">
        <div style={{ marginBottom: 8, display: "flex", alignItems: "center" }}>
          <span style={{ ...promptStyle, color: "#bc3fbc" }}>PS&gt; </span>
          <code style={cmdStyle}>{psInstallCommand}</code>
          <CopyBtn text={psInstallCommand} />
        </div>
      </TerminalBlock>

      {/* Step 2: Activate */}
      <TerminalBlock title="Step 2 — 激活 Worker">
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}># 安装后终端会自动启动激活流程：</span>
        </div>
        <div style={{ marginBottom: 8 }}>
          <span style={successStyle}>  Visit: </span>
          <span style={{ color: "#58a6ff" }}>{activateUrl}</span>
          <CopyBtn text={activateUrl} />
        </div>
        <div style={{ marginBottom: 8 }}>
          <span style={successStyle}>  Enter code: </span>
          <span style={highlightStyle}>XXXX-YYYY</span>
        </div>
        <div>
          <span style={commentStyle}># 打开链接 → 输入终端显示的激活码 → 完成</span>
        </div>
      </TerminalBlock>

      {/* Step 3: Back here */}
      <TerminalBlock title="Step 3 — 开始使用">
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}># Worker 激活后自动连接，回到这里点击「刷新检测」</span>
        </div>
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}># 看到 Worker 上线后即可创建 Session，开始远程终端</span>
        </div>
        <div>
          <span style={successStyle}>  Done! Your terminal is ready.</span>
        </div>
      </TerminalBlock>

      {/* Actions */}
      <div style={{ padding: "0 16px", display: "flex", gap: 8 }}>
        <IonButton
          routerLink="/activate"
        >
          <IonIcon slot="start" icon={keyOutline} />
          输入激活码
        </IonButton>
      </div>
    </div>
  );
}
