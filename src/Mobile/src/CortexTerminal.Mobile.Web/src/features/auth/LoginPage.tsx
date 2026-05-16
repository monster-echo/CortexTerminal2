import { useState, useEffect, useRef } from "react";
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
  IonSegment,
  IonSegmentButton,
  IonText,
} from "@ionic/react";
import { logoApple, logoGithub, logoGoogle, phonePortraitOutline } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import { authBridge } from "../../bridge/modules/authBridge";
import { useAuthStore, type AuthState } from "../../store/authStore";

const selectSetSession = (s: AuthState) => s.setSession;

export default function LoginPage() {
  const { t } = useTranslation();
  const platform = (window as any).initData?.platform ?? "unknown";
  const showAppleLogin = platform === "ios" || platform === "maccatalyst";
  const [loginMethod, setLoginMethod] = useState<"password" | "phone">("password");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [codeSent, setCodeSent] = useState(false);
  const [countdown, setCountdown] = useState(0);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [loadingProvider, setLoadingProvider] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | undefined>(undefined);
  const setSession = useAuthStore(selectSetSession);

  useEffect(() => {
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, []);

  useEffect(() => {
    if (countdown <= 0 && timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = undefined;
    }
  }, [countdown]);

  const handleSendCode = async () => {
    if (phone.length !== 11) {
      setErrorMessage(t("login.errorPhone"));
      return;
    }
    setErrorMessage(null);
    setLoadingProvider("phone");
    try {
      await authBridge.sendPhoneCode(phone);
      setCodeSent(true);
      setCountdown(60);
      timerRef.current = setInterval(() => setCountdown((c) => c - 1), 1000);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : t("login.errorSendCode"));
    } finally {
      setLoadingProvider(null);
    }
  };

  const handlePhoneLogin = async () => {
    if (code.length < 4) {
      setErrorMessage(t("login.errorCode"));
      return;
    }
    setErrorMessage(null);
    setLoadingProvider("phone-login");
    try {
      const result = await authBridge.verifyPhoneCode(phone, code);
      if (result.username) {
        setSession({ username: result.username }, "phone-token");
      }
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : t("login.errorVerify"));
    } finally {
      setLoadingProvider(null);
    }
  };

  const handleOAuth = async (provider: "github" | "google" | "apple") => {
    setErrorMessage(null);
    setLoadingProvider(provider);
    try {
      await authBridge.startOAuth(provider);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : t("login.errorBrowser"));
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
      }
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : t("login.errorPasswordLogin"));
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
          <IonLabel>
            <h1>{t("login.title")}</h1>
          </IonLabel>
          <IonNote>{t("login.subtitle")}</IonNote>

          <IonSegment
            value={loginMethod}
            onIonChange={(e) => setLoginMethod(e.detail.value as "password" | "phone")}
            style={{ maxWidth: 400, width: "100%", marginTop: 16 }}
          >
            <IonSegmentButton value="password">
              <IonLabel>{t("login.passwordLogin")}</IonLabel>
            </IonSegmentButton>
            <IonSegmentButton value="phone">
              <IonLabel>{t("login.phoneLogin")}</IonLabel>
            </IonSegmentButton>
          </IonSegment>

          {loginMethod === "password" && (
            <>
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

              <IonButton
                expand="block"
                style={btnStyle}
                onClick={handlePasswordLogin}
                disabled={loadingProvider !== null || !username.trim() || !password.trim()}
              >
                {loadingProvider === "password" ? <IonSpinner name="crescent" /> : t("login.passwordLogin")}
              </IonButton>
            </>
          )}

          {loginMethod === "phone" && (
            <>
              <IonList lines="none" className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
                <IonItem>
                  <IonNote slot="start">+86</IonNote>
                  <IonInput
                    type="tel"
                    maxlength={11}
                    placeholder={t("login.phonePlaceholder")}
                    value={phone}
                    onIonInput={(e) => setPhone((e.detail.value ?? "").replace(/\D/g, ""))}
                    disabled={loadingProvider !== null}
                  />
                </IonItem>
                <IonItem>
                  <IonInput
                    type="number"
                    maxlength={6}
                    placeholder={t("login.codePlaceholder")}
                    value={code}
                    onIonInput={(e) => setCode((e.detail.value ?? "").replace(/\D/g, ""))}
                    disabled={loadingProvider !== null || !codeSent}
                  />
                  <IonButton
                    slot="end"
                    fill="outline"
                    size="small"
                    onClick={handleSendCode}
                    disabled={loadingProvider !== null || countdown > 0 || phone.length !== 11}
                  >
                    {loadingProvider === "phone" ? (
                      <IonSpinner name="crescent" />
                    ) : countdown > 0 ? (
                      `${countdown}s`
                    ) : codeSent ? (
                      t("login.resend")
                    ) : (
                      t("login.getCode")
                    )}
                  </IonButton>
                </IonItem>
              </IonList>

              {codeSent && (
                <IonButton
                  expand="block"
                  style={btnStyle}
                  onClick={handlePhoneLogin}
                  disabled={loadingProvider !== null || code.length < 4}
                >
                  {loadingProvider === "phone-login" ? (
                    <IonSpinner name="crescent" />
                  ) : (
                    <>
                      <IonIcon slot="start" icon={phonePortraitOutline} />
                      {t("login.login")}
                    </>
                  )}
                </IonButton>
              )}
            </>
          )}

          <IonItem lines="none" className="ion-padding-top" style={{ maxWidth: 400 }}>
            <IonNote className="ion-text-center" style={{ width: "100%" }}>
              {t("login.orSignInWith")}
            </IonNote>
          </IonItem>

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

          {errorMessage && (
            <IonText color="danger" className="ion-padding-top">
              <p>{errorMessage}</p>
            </IonText>
          )}
        </div>
      </IonContent>
    </IonPage>
  );
}
