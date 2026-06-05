import { useState, useEffect } from "react";
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
import { logoApple, logoGithub, logoGoogle } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import { authBridge } from "../../bridge/modules/authBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import { useAuthStore, type AuthState } from "../../store/authStore";
import { useAppStore, type AppStoreState } from "../../store/appStore";
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

export default function LoginPage() {
  const { t } = useTranslation();
  const appInfo = useAppStore(selectAppInfo);
  const platform = (window as any).initData?.platform ?? "unknown";
  const showAppleLogin = platform === "ios" || platform === "maccatalyst";
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [loadingProvider, setLoadingProvider] = useState<string | null>(null);
  const setSession = useAuthStore(selectSetSession);
  const isDark = useIsDark();
  const logoSrc = isDark ? logoSvg : logoLightSvg;

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

  const handlePasswordLogin = async () => {
    if (!username.trim() || !password.trim()) {
      setErrorMessage(t("login.errorPasswordLogin"));
      return;
    }
    setErrorMessage(null);
    setLoadingProvider("password");
    try {
      const result = await authBridge.loginWithPassword(username, password);
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

  const btnStyle = { maxWidth: 400, width: "100%" } as React.CSSProperties;

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

          <IonList lines="none" className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
            <IonItem>
              <IonInput
                type="text"
                placeholder={t("login.usernamePlaceholder")}
                value={username}
                onIonInput={(e) => setUsername(e.detail.value ?? "")}
                disabled={loadingProvider !== null}
              />
            </IonItem>
            <IonItem>
              <IonInput
                type="password"
                placeholder={t("login.passwordPlaceholder")}
                value={password}
                onIonInput={(e) => setPassword(e.detail.value ?? "")}
                disabled={loadingProvider !== null}
                onKeyDown={(e) => { if (e.key === "Enter") handlePasswordLogin(); }}
              />
            </IonItem>
          </IonList>

          {errorMessage && (
            <IonText color="danger" style={{ maxWidth: 400, width: "100%", textAlign: "left" }}>
              <p style={{ fontSize: 13, paddingLeft: 16 }}>{errorMessage}</p>
            </IonText>
          )}

          <IonButton
            expand="block"
            style={btnStyle}
            onClick={handlePasswordLogin}
            disabled={loadingProvider !== null || !username.trim() || !password.trim()}
          >
            {loadingProvider === "password" ? <IonSpinner name="crescent" /> : t("login.passwordLogin")}
          </IonButton>

          <div style={{ width: "100%", maxWidth: 400, textAlign: "center", paddingTop: 16, fontSize: 13, color: "var(--ion-color-medium)" }}>
            {t("login.orSignInWith")}
          </div>

          <div className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
            {showAppleLogin && (
              <IonButton
                expand="block"
                fill="outline"
                className="ion-margin-bottom"
                onClick={() => handleOAuth("apple")}
                disabled={loadingProvider !== null}
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
            <IonButton
              expand="block"
              fill="outline"
              className="ion-margin-bottom"
              onClick={() => handleOAuth("github")}
              disabled={loadingProvider !== null}
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
            <IonButton
              expand="block"
              fill="outline"
              onClick={() => handleOAuth("google")}
              disabled={loadingProvider !== null}
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
          </div>

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
    </IonPage>
  );
}
