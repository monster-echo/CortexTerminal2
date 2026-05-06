import { useState, useEffect, useRef } from "react"
import { useTranslation } from "react-i18next"
import {
  IonPage,
  IonContent,
  IonButton,
  IonText,
  IonIcon,
  IonSpinner,
  IonInput,
  IonList,
  IonItem,
  IonNote,
  IonLabel,
} from "@ionic/react"
import { terminalOutline, logoGithub, logoGoogle, phonePortraitOutline } from "ionicons/icons"
import type { NativeBridge } from "../bridge/types"

export function LoginPage({
  bridge,
  onLogin,
}: {
  bridge: NativeBridge
  onLogin: () => void
}) {
  const { t } = useTranslation()
  const [phone, setPhone] = useState("")
  const [code, setCode] = useState("")
  const [codeSent, setCodeSent] = useState(false)
  const [countdown, setCountdown] = useState(0)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [loadingProvider, setLoadingProvider] = useState<string | null>(null)
  const timerRef = useRef<ReturnType<typeof setInterval> | undefined>(undefined)

  useEffect(() => {
    return () => {
      if (timerRef.current) clearInterval(timerRef.current)
    }
  }, [])

  useEffect(() => {
    if (countdown <= 0 && timerRef.current) {
      clearInterval(timerRef.current)
      timerRef.current = undefined
    }
  }, [countdown])

  const handleSendCode = async () => {
    if (phone.length !== 11) {
      setErrorMessage(t('auth.errorPhoneInvalid'))
      return
    }
    setErrorMessage(null)
    setLoadingProvider("phone")
    try {
      await bridge.request("auth", "phone.sendCode", { phone })
      setCodeSent(true)
      setCountdown(60)
      timerRef.current = setInterval(() => {
        setCountdown((c) => c - 1)
      }, 1000)
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : t('auth.errorSendCode'),
      )
    } finally {
      setLoadingProvider(null)
    }
  }

  const handlePhoneLogin = async () => {
    if (code.length < 4) {
      setErrorMessage(t('auth.errorCodeRequired'))
      return
    }
    setErrorMessage(null)
    setLoadingProvider("phone-login")
    try {
      await bridge.request("auth", "phone.verifyCode", { phone, code })
      onLogin()
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : t('auth.errorVerify'),
      )
    } finally {
      setLoadingProvider(null)
    }
  }

  const handleOAuth = async (provider: "github" | "google" | "apple") => {
    setErrorMessage(null)
    setLoadingProvider(provider)
    try {
      await bridge.request("auth", "oauth.start", { provider })
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : t('auth.errorBrowser'),
      )
      setLoadingProvider(null)
    }
  }

  return (
    <IonPage>
      <IonContent className="ion-padding">
        <div className="ion-text-center" style={{ minHeight: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
          <IonIcon icon={terminalOutline} color="primary" className="ion-padding" style={{ fontSize: 48 }} />
          <IonLabel><h1>CortexTerminal</h1></IonLabel>
          <IonNote>{t('auth.signInToContinue')}</IonNote>

          {/* Phone number login */}
          <IonList lines="none" className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
            <IonItem>
              <IonNote slot="start">+86</IonNote>
              <IonInput
                type="tel"
                maxlength={11}
                placeholder={t('auth.phonePlaceholder')}
                value={phone}
                onIonInput={(e) => setPhone((e.detail.value ?? "").replace(/\D/g, ""))}
                disabled={loadingProvider !== null}
              />
            </IonItem>

            <IonItem>
              <IonInput
                type="number"
                maxlength={6}
                placeholder={t('auth.codePlaceholder')}
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
                  t('auth.resend')
                ) : (
                  t('auth.getCode')
                )}
              </IonButton>
            </IonItem>
          </IonList>

          {codeSent && (
            <IonButton
              expand="block"
              className="ion-padding-horizontal"
              style={{ maxWidth: 400 }}
              onClick={handlePhoneLogin}
              disabled={loadingProvider !== null || code.length < 4}
            >
              {loadingProvider === "phone-login" ? (
                <IonSpinner name="crescent" />
              ) : (
                <>
                  <IonIcon slot="start" icon={phonePortraitOutline} />
                  {t('auth.login')}
                </>
              )}
            </IonButton>
          )}

          {/* Divider */}
          <IonItem lines="none" className="ion-padding-top" style={{ maxWidth: 400 }}>
            <IonNote className="ion-text-center" style={{ width: "100%" }}>
              {t('auth.orSignInWith')}
            </IonNote>
          </IonItem>

          {/* OAuth buttons */}
          <div className="ion-padding-top" style={{ width: "100%", maxWidth: 400 }}>
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
                t('auth.signInWithApple')
              )}
            </IonButton>
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
                  {t('auth.continueWithGithub')}
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
                  {t('auth.continueWithGoogle')}
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
  )
}
