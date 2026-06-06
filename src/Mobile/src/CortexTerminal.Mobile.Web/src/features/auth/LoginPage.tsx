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
  IonSegment,
  IonSegmentButton,
} from "@ionic/react";
import { logoApple, logoGithub, logoGoogle } from "ionicons/icons";
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

export default function LoginPage() {
  const { t } = useTranslation();
  const appInfo = useAppStore(selectAppInfo);
  const platform = (window as any).initData?.platform ?? "unknown";
  const showAppleLogin = platform === "ios" || platform === "maccatalyst";

  const [availableMethods, setAvailableMethods] = useState<string[]>([]);
  const [methodsLoaded, setMethodsLoaded] = useState(false);
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
      .then((result) => {
        setAvailableMethods(result.methods);
        setMethodsLoaded(true);
      })
      .catch(() => {
        setAvailableMethods(["password", "github", "google", "apple"]);
        setMethodsLoaded(true);
      });
  }, []);

  const showPhoneLogin = availableMethods.includes("phone");
  const showGithub = availableMethods.includes("github");
  const showGoogle = availableMethods.includes("google");
  const showApple = showAppleLogin && availableMethods.includes("apple");

  // Auto-switch tab: if phone is available, default to phone for China
  useEffect(() => {
    if (methodsLoaded && showPhoneLogin) {
      setActiveTab("phone");
    }
  }, [methodsLoaded, showPhoneLogin]);

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
      if (result.username) {
        setSession({ username: result.username }, "password-token");
        nativeBridge.trackEvent("login", { method: "password" });
      }
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
  const isLoading = loadingProvider !== null;

  const hasOAuth = showGithub || showGoogle || showApple;

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

          {/* Tab switcher: only show if phone login is available */}
          {showPhoneLogin && (
            <IonSegment
              value={activeTab}
              onIonChange={(e) => setActiveTab(e.detail.value as LoginTab)}
              style={{ maxWidth: 400, width: "100%", marginTop: 16 }}
            >
              <IonSegmentButton value="phone">
                <IonLabel>{t("login.phoneLogin")}</IonLabel>
              </IonSegmentButton>
              <IonSegmentButton value="password">
                <IonLabel>{t("login.passwordLogin")}</IonLabel>
              </IonSegmentButton>
            </IonSegment>
          )}

          {/* Phone login form */}
          {showPhoneLogin && activeTab === "phone" && (
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
                  />
                  <IonButton
                    slot="end"
                    fill="clear"
                    size="small"
                    onClick={() => handleSendCode()}
                    disabled={isLoading || codeCountdown > 0 || phone.length !== 11}
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
              >
                {loadingProvider === "phone" ? <IonSpinner name="crescent" /> : t("login.login")}
              </IonButton>
            </>
          )}

          {/* Password login form */}
          {((!showPhoneLogin) || activeTab === "password") && (
            <>
              <IonList lines="none" className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
                <IonItem>
                  <IonInput
                    type="text"
                    placeholder={t("login.usernamePlaceholder")}
                    value={username}
                    onIonInput={(e) => setUsername(e.detail.value ?? "")}
                    disabled={isLoading}
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
                  />
                </IonItem>
              </IonList>

              <IonButton
                expand="block"
                style={btnStyle}
                onClick={() => handlePasswordLogin()}
                disabled={isLoading || !username.trim() || !password.trim()}
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

          {hasOAuth && (
            <>
              <div style={{ width: "100%", maxWidth: 400, textAlign: "center", paddingTop: 16, fontSize: 13, color: "var(--ion-color-medium)" }}>
                {t("login.orSignInWith")}
              </div>

              <div className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
                {showApple && (
                  <IonButton
                    expand="block"
                    fill="outline"
                    className="ion-margin-bottom"
                    onClick={() => handleOAuth("apple")}
                    disabled={isLoading}
                  >
                    {loadingProvider === "apple" ? (
                      <IonSpinner name="crescent" />
                    ) : (
                      <>
                        <IonIcon slot="start" icon={logoApple} />
                        {t("login.signInApple")}
                      </>
                    )}
                  </IonButton>
                )}
                {showGithub && (
                  <IonButton
                    expand="block"
                    fill="outline"
                    className="ion-margin-bottom"
                    onClick={() => handleOAuth("github")}
                    disabled={isLoading}
                  >
                    {loadingProvider === "github" ? (
                      <IonSpinner name="crescent" />
                    ) : (
                      <>
                        <IonIcon slot="start" icon={logoGithub} />
                        {t("login.continueGithub")}
                      </>
                    )}
                  </IonButton>
                )}
                {showGoogle && (
                  <IonButton
                    expand="block"
                    fill="outline"
                    onClick={() => handleOAuth("google")}
                    disabled={isLoading}
                  >
                    {loadingProvider === "google" ? (
                      <IonSpinner name="crescent" />
                    ) : (
                      <>
                        <IonIcon slot="start" icon={logoGoogle} />
                        {t("login.continueGoogle")}
                      </>
                    )}
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
            >{t("settings.privacy")}</a>
            {t("login.agreementAnd")}
            <a
              onClick={(e) => { e.preventDefault(); nativeBridge.openExternalLink(appInfo?.termsOfServiceUrl ?? ""); }}
              style={{ color: "var(--ion-color-primary)", cursor: "pointer", textDecoration: "underline" }}
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
