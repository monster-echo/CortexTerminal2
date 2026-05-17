import { IonButton, IonIcon } from "@ionic/react";
import { checkmarkOutline, copyOutline, keyOutline } from "ionicons/icons";
import { useState } from "react";
import { useTranslation } from "react-i18next";

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
  const { t } = useTranslation();

  return (
    <div style={{ paddingBottom: 24 }}>
      {/* Intro */}
      <TerminalBlock title={t("sessionInstall.introTitle")}>
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}>{t("sessionInstall.noSession")}</span>
        </div>
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}>{t("sessionInstall.needWorker")}</span>
        </div>
        <div>
          <span style={successStyle}>{t("sessionInstall.followSteps")}</span>
        </div>
      </TerminalBlock>

      {/* Step 1: Install macOS/Linux */}
      <TerminalBlock title={t("sessionInstall.step1Mac")}>
        <div style={{ marginBottom: 8, display: "flex", alignItems: "center" }}>
          <span style={promptStyle}>$ </span>
          <code style={cmdStyle}>{bashInstallCommand}</code>
          <CopyBtn text={bashInstallCommand} />
        </div>
      </TerminalBlock>

      {/* Step 1 alt: Windows */}
      <TerminalBlock title={t("sessionInstall.step1Win")}>
        <div style={{ marginBottom: 8, display: "flex", alignItems: "center" }}>
          <span style={{ ...promptStyle, color: "#bc3fbc" }}>PS&gt; </span>
          <code style={cmdStyle}>{psInstallCommand}</code>
          <CopyBtn text={psInstallCommand} />
        </div>
      </TerminalBlock>

      {/* Step 2: Activate */}
      <TerminalBlock title={t("sessionInstall.step2Activate")}>
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}>{t("sessionInstall.autoActivate")}</span>
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
          <span style={commentStyle}>{t("sessionInstall.openLink")}</span>
        </div>
      </TerminalBlock>

      {/* Step 3: Back here */}
      <TerminalBlock title={t("sessionInstall.step3Start")}>
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}>{t("sessionInstall.backRefresh")}</span>
        </div>
        <div style={{ marginBottom: 12 }}>
          <span style={commentStyle}>{t("sessionInstall.createSession")}</span>
        </div>
        <div>
          <span style={successStyle}>{t("sessionInstall.ready")}</span>
        </div>
      </TerminalBlock>

      {/* Actions */}
      <div style={{ padding: "0 16px", display: "flex", gap: 8 }}>
        <IonButton
          routerLink="/activate"
        >
          <IonIcon slot="start" icon={keyOutline} />
          {t("sessionInstall.enterCode")}
        </IonButton>
      </div>
    </div>
  );
}
