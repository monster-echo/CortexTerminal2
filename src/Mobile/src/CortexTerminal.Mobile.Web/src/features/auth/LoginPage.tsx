import { useState, useEffect, useCallback, useRef } from "react";
import {
  IonPage,
  IonContent,
  IonButton,
  IonIcon,
  IonSpinner,
  IonInput,
  IonList,
  IonItem,
  IonNote,
  IonLabel,
  IonText,
} from "@ionic/react";
import { logoApple, logoGithub, phonePortraitOutline } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import { authBridge } from "../../bridge/modules/authBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import { useAuthStore, type AuthState } from "../../store/authStore";
import { useAppStore, type AppStoreState } from "../../store/appStore";
import { SliderCaptchaModal } from "./SliderCaptchaModal";
import logoSvg from "../../assets/logo.svg";
import logoLightSvg from "../../assets/logo-dark.svg";

const selectSetSession = (s: AuthState) => s.setSession;
const selectAppInfo = (s: AppStoreState) => s.appInfo;

function useIsDark() {
  const [isDark, setIsDark] = useState(() =>
    document.documentElement.classList.contains("ion-palette-dark")
  );
  useEffect(() => {
    const observer = new MutationObserver(() =>
      setIsDark(document.documentElement.classList.contains("ion-palette-dark"))
    );
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
    return () => observer.disconnect();
  }, []);
  return isDark;
}

type LoginTab = "password" | "phone";

// Google 官方多色 G 图标（ionicons 的 logoGoogle 是单色，辨识度不够）
function GoogleColorIcon({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 48 48" aria-hidden="true">
      <path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z" />
      <path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z" />
      <path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.211 35.091 26.715 36 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z" />
      <path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303c-.792 2.237-2.231 4.166-4.087 5.571.001-.001 6.19 5.238 6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z" />
    </svg>
  );
}

export default function LoginPage() {
  const { t } = useTranslation();
  const appInfo = useAppStore(selectAppInfo);
  const platform = (window as any).initData?.platform ?? "unknown";
  const showAppleLogin = platform === "ios" || platform === "maccatalyst";

  const [availableMethods, setAvailableMethods] = useState<string[]>([]);
  const [activeTab, setActiveTab] = useState<LoginTab>("password");

  // Password fields
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");

  // Phone fields
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [codeCountdown, setCodeCountdown] = useState(0);

  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [loadingProvider, setLoadingProvider] = useState<string | null>(null);
  const setSession = useAuthStore(selectSetSession);
  const isDark = useIsDark();
  const logoSrc = isDark ? logoSvg : logoLightSvg;

  // Captcha state
  const [captchaOpen, setCaptchaOpen] = useState(false);
  const pendingActionRef = useRef<((captchaToken: string) => void) | null>(null);

  // Fetch available auth methods
  useEffect(() => {
    authBridge.getAvailableAuthMethods()
      .then((result) => setAvailableMethods(result.methods))
      .catch(() => setAvailableMethods(["password", "github", "google", "apple"]));
  }, []);

  const showPhoneLogin = availableMethods.includes("phone");
  const showGithub = availableMethods.includes("github");
  const showGoogle = availableMethods.includes("google");
  const showApple = showAppleLogin && availableMethods.includes("apple");

  // Countdown timer for SMS code
  useEffect(() => {
    if (codeCountdown <= 0) return;
    const timer = setTimeout(() => setCodeCountdown(codeCountdown - 1), 1000);
    return () => clearTimeout(timer);
  }, [codeCountdown]);

  const handleCaptchaRequired = useCallback((action: (captchaToken: string) => void) => {
    pendingActionRef.current = action;
    setCaptchaOpen(true);
  }, []);

  const handleCaptchaSuccess = useCallback((captchaToken: string) => {
    setCaptchaOpen(false);
    pendingActionRef.current?.(captchaToken);
    pendingActionRef.current = null;
  }, []);

  const handleOAuth = async (provider: "github" | "google" | "apple") => {
    setErrorMessage(null);
    setLoadingProvider(provider);
    try {
      nativeBridge.trackEvent("login", { method: provider });
      await authBridge.startOAuth(provider);
    } catch (error) {
      setErrorMessage((error instanceof Error ? error.message : "") || t("login.errorBrowser"));
      setLoadingProvider(null);
    }
  };

  const handlePasswordLogin = async (captchaToken?: string | null) => {
    if (!username.trim() || !password.trim()) {
      setErrorMessage(t("login.errorPasswordLogin"));
      return;
    }
    setErrorMessage(null);
    setLoadingProvider("password");
    try {
      const result = await authBridge.loginWithPassword(username, password, captchaToken ?? null);
      if (result.captchaRequired) {
        setLoadingProvider(null);
        handleCaptchaRequired((token) => handlePasswordLogin(token));
        return;
      }
      if (!result.success || !result.username) {
        setErrorMessage(t("login.errorPasswordLogin"));
        return;
      }
      setSession({ username: result.username }, "password-token");
      nativeBridge.trackEvent("login", { method: "password" });
    } catch (error) {
      setErrorMessage((error instanceof Error ? error.message : "") || t("login.errorPasswordLogin"));
    } finally {
      setLoadingProvider(null);
    }
  };

  const handleSendCode = useCallback(async (captchaToken?: string | null) => {
    if (phone.length !== 11 || !/^\d{11}$/.test(phone)) {
      setErrorMessage(t("login.errorPhone"));
      return;
    }
    setErrorMessage(null);
    setLoadingProvider("sms");
    try {
      const result = await authBridge.sendPhoneCode(phone, captchaToken ?? null);
      if (result.captchaRequired) {
        setLoadingProvider(null);
        handleCaptchaRequired((token) => handleSendCode(token));
        return;
      }
      if (!result.success) {
        setErrorMessage(t("login.errorSendCode"));
        return;
      }
      setCodeCountdown(60);
    } catch (error) {
      const msg = error instanceof Error ? error.message : "";
      if (msg.startsWith("RATE_LIMITED:")) {
        const seconds = parseInt(msg.split(":")[1], 10);
        setCodeCountdown(seconds);
      } else {
        setErrorMessage(msg || t("login.errorSendCode"));
      }
    } finally {
      setLoadingProvider(null);
    }
  }, [phone, t, handleCaptchaRequired]);

  const handlePhoneLogin = async () => {
    if (!code.trim()) {
      setErrorMessage(t("login.errorCode"));
      return;
    }
    setErrorMessage(null);
    setLoadingProvider("phone");
    try {
      const result = await authBridge.verifyPhoneCode(phone, code);
      if (result.username) {
        setSession({ username: result.username }, "phone-token");
        nativeBridge.trackEvent("login", { method: "phone" });
      }
    } catch (error) {
      setErrorMessage((error instanceof Error ? error.message : "") || t("login.errorVerify"));
    } finally {
      setLoadingProvider(null);
    }
  };

  const btnStyle = { maxWidth: 400, width: "100%" } as React.CSSProperties;
  const iconBtnStyle = {
    width: 48,
    height: 48,
    "--padding-start": "0",
    "--padding-end": "0",
    "--box-shadow": "none",
    margin: "0 4px",
  } as React.CSSProperties;
  const isLoading = loadingProvider !== null;

  const hasOAuth = showGithub || showGoogle || showApple;
  // 手机号入口仅在密码表单态出现；切到手机表单后它就是当前方式，不再重复列出
  const showPhoneButton = showPhoneLogin && activeTab === "password";
  // 底部「其他方式」整排只在密码表单态显示；手机表单态聚焦，不再露出第三方入口
  const showOtherRow = activeTab === "password" && (showPhoneLogin || hasOAuth);

  return (
    <IonPage>
      <IonContent className="ion-padding">
        <div
          className="ion-text-center"
          style={{
            minHeight: "100%",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <img src={logoSrc} alt="" style={{ width: 64, height: 64, marginBottom: 8 }} />
          <IonLabel>
            <h1>{t("login.title")}</h1>
          </IonLabel>
          <IonNote>{t("login.subtitle")}</IonNote>

          {/* 手机号表单态：顶部给一个返回账号密码登录的入口 */}
          {activeTab === "phone" && (
            <div style={{ width: "100%", maxWidth: 400, textAlign: "left", marginTop: 12, marginBottom: 4 }}>
              <span
                onClick={() => { if (!isLoading) setActiveTab("password"); }}
                style={{ fontSize: 13, color: "var(--ion-color-primary)", cursor: "pointer" }}
                data-analytics-id="login_back_to_password"
              >
                ← {t("login.usePasswordLogin")}
              </span>
            </div>
          )}

          {/* Phone login form */}
          {activeTab === "phone" && (
            <>
              <IonList lines="none" className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
                <IonItem>
                  <IonInput
                    type="tel"
                    placeholder={t("login.phonePlaceholder")}
                    value={phone}
                    onIonInput={(e) => setPhone(e.detail.value ?? "")}
                    disabled={isLoading}
                    maxlength={11}
                    data-analytics-id="login_phone"
                  />
                </IonItem>
                <IonItem>
                  <IonInput
                    type="text"
                    placeholder={t("login.codePlaceholder")}
                    value={code}
                    onIonInput={(e) => setCode(e.detail.value ?? "")}
                    disabled={isLoading}
                    onKeyDown={(e) => { if (e.key === "Enter") handlePhoneLogin(); }}
                    style={{ flex: 1 }}
                    data-analytics-id="login_code"
                  />
                  <IonButton
                    slot="end"
                    fill="clear"
                    size="small"
                    onClick={() => handleSendCode()}
                    disabled={isLoading || codeCountdown > 0 || phone.length !== 11}
                    data-analytics-id="login_send_code"
                  >
                    {codeCountdown > 0
                      ? t("login.resend") + ` (${codeCountdown}s)`
                      : t("login.getCode")}
                  </IonButton>
                </IonItem>
              </IonList>

              <IonButton
                expand="block"
                style={btnStyle}
                onClick={handlePhoneLogin}
                disabled={isLoading || !code.trim() || phone.length !== 11}
                data-analytics-id="login_submit_phone"
              >
                {loadingProvider === "phone" ? <IonSpinner name="crescent" /> : t("login.login")}
              </IonButton>
            </>
          )}

          {/* Password login form (默认) */}
          {activeTab === "password" && (
            <>
              <IonList lines="none" className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
                <IonItem>
                  <IonInput
                    type="text"
                    placeholder={t("login.usernamePlaceholder")}
                    value={username}
                    onIonInput={(e) => setUsername(e.detail.value ?? "")}
                    disabled={isLoading}
                    data-analytics-id="login_username"
                  />
                </IonItem>
                <IonItem>
                  <IonInput
                    type="password"
                    placeholder={t("login.passwordPlaceholder")}
                    value={password}
                    onIonInput={(e) => setPassword(e.detail.value ?? "")}
                    disabled={isLoading}
                    onKeyDown={(e) => { if (e.key === "Enter") handlePasswordLogin(); }}
                    data-analytics-id="login_password"
                  />
                </IonItem>
              </IonList>

              <IonButton
                expand="block"
                style={btnStyle}
                onClick={() => handlePasswordLogin()}
                disabled={isLoading || !username.trim() || !password.trim()}
                data-analytics-id="login_submit_password"
              >
                {loadingProvider === "password" ? <IonSpinner name="crescent" /> : t("login.passwordLogin")}
              </IonButton>
            </>
          )}

          {errorMessage && (
            <IonText color="danger" style={{ maxWidth: 400, width: "100%", textAlign: "left" }}>
              <p style={{ fontSize: 13, paddingLeft: 16 }}>{errorMessage}</p>
            </IonText>
          )}

          {/* 其他方式：一排圆形小图标（手机号 + 第三方） */}
          {showOtherRow && (
            <>
              <div style={{ display: "flex", alignItems: "center", width: "100%", maxWidth: 400, marginTop: 24, marginBottom: 12 }}>
                <div style={{ flex: 1, height: 1, background: "var(--ion-color-step-150, #ccc)" }} />
                <span style={{ padding: "0 14px", fontSize: 12, color: "var(--ion-color-medium)" }}>
                  {t("login.orSignInWith")}
                </span>
                <div style={{ flex: 1, height: 1, background: "var(--ion-color-step-150, #ccc)" }} />
              </div>

              <div style={{ display: "flex", justifyContent: "center", alignItems: "center", width: "100%", maxWidth: 400 }}>
                {showPhoneButton && (
                  <IonButton
                    shape="round"
                    fill="outline"
                    style={iconBtnStyle}
                    onClick={() => setActiveTab("phone")}
                    disabled={isLoading}
                    data-analytics-id="login_switch_phone"
                  >
                    <IonIcon icon={phonePortraitOutline} style={{ fontSize: 22 }} />
                  </IonButton>
                )}
                {showApple && (
                  <IonButton
                    shape="round"
                    fill="outline"
                    style={iconBtnStyle}
                    onClick={() => handleOAuth("apple")}
                    disabled={isLoading}
                    data-analytics-id="login_oauth_apple"
                  >
                    {loadingProvider === "apple"
                      ? <IonSpinner name="crescent" />
                      : <IonIcon icon={logoApple} style={{ fontSize: 22 }} />}
                  </IonButton>
                )}
                {showGithub && (
                  <IonButton
                    shape="round"
                    fill="outline"
                    style={iconBtnStyle}
                    onClick={() => handleOAuth("github")}
                    disabled={isLoading}
                    data-analytics-id="login_oauth_github"
                  >
                    {loadingProvider === "github"
                      ? <IonSpinner name="crescent" />
                      : <IonIcon icon={logoGithub} style={{ fontSize: 22 }} />}
                  </IonButton>
                )}
                {showGoogle && (
                  <IonButton
                    shape="round"
                    fill="outline"
                    style={iconBtnStyle}
                    onClick={() => handleOAuth("google")}
                    disabled={isLoading}
                    data-analytics-id="login_oauth_google"
                  >
                    {loadingProvider === "google"
                      ? <IonSpinner name="crescent" />
                      : <GoogleColorIcon size={22} />}
                  </IonButton>
                )}
              </div>
            </>
          )}

          <div style={{
            width: "100%", maxWidth: 400, textAlign: "center",
            padding: "16px 0 0", fontSize: 12,
            color: "var(--ion-color-medium)", lineHeight: 1.6,
          }}>
            {t("login.agreementPrefix")}
            <a
              onClick={(e) => { e.preventDefault(); nativeBridge.openExternalLink(appInfo?.privacyPolicyUrl ?? ""); }}
              style={{ color: "var(--ion-color-primary)", cursor: "pointer", textDecoration: "underline" }}
              data-analytics-id="login_privacy_link"
            >{t("settings.privacy")}</a>
            {t("login.agreementAnd")}
            <a
              onClick={(e) => { e.preventDefault(); nativeBridge.openExternalLink(appInfo?.termsOfServiceUrl ?? ""); }}
              style={{ color: "var(--ion-color-primary)", cursor: "pointer", textDecoration: "underline" }}
              data-analytics-id="login_terms_link"
            >{t("settings.terms")}</a>
            {t("login.agreementSuffix")}
          </div>
        </div>
      </IonContent>

      <SliderCaptchaModal
        isOpen={captchaOpen}
        onClose={() => { setCaptchaOpen(false); pendingActionRef.current = null; }}
        onSuccess={handleCaptchaSuccess}
      />
    </IonPage>
  );
}
