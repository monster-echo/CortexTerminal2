import {
  IonButton,
  IonCol,
  IonContent,
  IonGrid,
  IonIcon,
  IonInput,
  IonPage,
  IonRow,
  IonSpinner,
  IonText,
} from "@ionic/react";
import { checkmarkCircleOutline, closeCircleOutline, keyOutline } from "ionicons/icons";
import { useState } from "react";
import PageHeader from "../../components/PageHeader";
import { useAuthStore } from "../../store/authStore";

const gatewayBaseUri = "https://gateway.ct.rwecho.top";

type ActivateState = "input" | "submitting" | "success" | "error";

export default function ActivatePage() {
  const [code, setCode] = useState("");
  const [state, setState] = useState<ActivateState>("input");
  const [errorMsg, setErrorMsg] = useState("");
  const token = useAuthStore((s) => s.token);

  const handleSubmit = async () => {
    const trimmed = code.trim().toUpperCase();
    if (trimmed.length !== 9 || trimmed[4] !== "-") {
      setErrorMsg("激活码格式应为 XXXX-YYYY");
      setState("error");
      return;
    }

    setState("submitting");
    setErrorMsg("");

    try {
      const res = await fetch(`${gatewayBaseUri}/api/auth/device-flow/verify`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ userCode: trimmed }),
      });

      if (res.ok) {
        setState("success");
      } else {
        const data = await res.json().catch(() => ({}));
        if (res.status === 400 || data.error === "invalid_code") {
          setErrorMsg("激活码无效或已过期，请检查终端上显示的码后重试");
        } else if (res.status === 401) {
          setErrorMsg("登录已过期，请重新登录后再试");
        } else {
          setErrorMsg(`激活失败 (${res.status})，请稍后重试`);
        }
        setState("error");
      }
    } catch {
      setErrorMsg("网络错误，请检查网络连接后重试");
      setState("error");
    }
  };

  const handleInputChange = (e: CustomEvent) => {
    const val = (e.detail.value ?? "").toUpperCase();
    setCode(val);
    if (state === "error") setState("input");
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") {
      e.preventDefault();
      void handleSubmit();
    }
  };

  return (
    <IonPage>
      <PageHeader title="激活 Worker" defaultHref="/sessions" />
      <IonContent fullscreen>
        <IonGrid style={{ padding: "16px 0" }}>
          <IonRow className="ion-justify-content-center">
            <IonCol size="12" size-md="8" size-lg="6">
              {state === "success" ? (
                /* ── Success state ── */
                <div style={{ textAlign: "center", padding: "64px 16px 32px" }}>
                  <IonIcon
                    icon={checkmarkCircleOutline}
                    style={{ fontSize: 64, color: "var(--ion-color-success, #2dd36f)" }}
                  />
                  <h2 style={{ margin: "16px 0 8px", fontSize: 20, fontWeight: 700 }}>
                    Worker 已激活
                  </h2>
                  <p
                    style={{
                      color: "var(--ion-color-medium, #92949c)",
                      fontSize: 14,
                      lineHeight: 1.5,
                      margin: "0 0 24px",
                    }}
                  >
                    Worker 已成功连接到 Gateway，现在可以返回创建 Session 了。
                  </p>
                  <IonButton
                    expand="block"
                    routerLink="/sessions"
                    routerDirection="back"
                  >
                    返回首页
                  </IonButton>
                </div>
              ) : (
                /* ── Input / Error state ── */
                <div style={{ textAlign: "center", padding: "48px 16px 32px" }}>
                  <div
                    style={{
                      width: 72,
                      height: 72,
                      borderRadius: 20,
                      background: "var(--ion-color-primary-tint, rgba(56,128,255,0.15))",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      margin: "0 auto 16px",
                    }}
                  >
                    <IonIcon
                      icon={keyOutline}
                      style={{ fontSize: 36, color: "var(--ion-color-primary, #3880ff)" }}
                    />
                  </div>
                  <IonText>
                    <h2 style={{ margin: "0 0 8px", fontSize: 20, fontWeight: 700 }}>
                      输入激活码
                    </h2>
                    <p
                      style={{
                        color: "var(--ion-color-medium, #92949c)",
                        fontSize: 14,
                        lineHeight: 1.5,
                        margin: 0,
                      }}
                    >
                      在终端运行 <code style={{ fontFamily: "monospace" }}>cortex login</code> 后，
                      屏幕会显示一个 XXXX-YYYY 格式的激活码。
                    </p>
                  </IonText>
                </div>
              )}

              {state !== "success" && (
                <>
                  <IonInput
                    value={code}
                    onIonInput={handleInputChange}
                    onKeyDown={handleKeyDown}
                    placeholder="XXXX-YYYY"
                    maxlength={9}
                    debounce={0}
                    style={{
                      fontFamily: "'SF Mono', 'Menlo', 'Monaco', monospace",
                      fontSize: 28,
                      letterSpacing: 4,
                      textAlign: "center",
                      background: "var(--ion-color-light, #f4f5f8)",
                      borderRadius: 12,
                      padding: "14px 16px",
                      margin: "0 16px",
                      "--padding-start": "0",
                      "--padding-end": "0",
                    }}
                  />

                  {state === "error" && errorMsg && (
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 6,
                        margin: "12px 16px 0",
                        color: "var(--ion-color-danger, #eb445a)",
                        fontSize: 13,
                      }}
                    >
                      <IonIcon icon={closeCircleOutline} style={{ fontSize: 16, flexShrink: 0 }} />
                      {errorMsg}
                    </div>
                  )}

                  <div style={{ padding: "20px 16px 0" }}>
                    <IonButton
                      expand="block"
                      size="large"
                      disabled={state === "submitting" || code.trim().length < 9}
                      onClick={() => void handleSubmit()}
                    >
                      {state === "submitting" ? (
                        <IonSpinner name="crescent" />
                      ) : (
                        "确认激活"
                      )}
                    </IonButton>
                  </div>
                </>
              )}
            </IonCol>
          </IonRow>
        </IonGrid>
      </IonContent>
    </IonPage>
  );
}
