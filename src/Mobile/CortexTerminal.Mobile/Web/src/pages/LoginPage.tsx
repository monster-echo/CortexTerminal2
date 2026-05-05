import { useState, useEffect, useRef } from "react"
import {
  IonPage,
  IonContent,
  IonButton,
  IonText,
  IonIcon,
  IonSpinner,
  IonInput,
} from "@ionic/react"
import { terminalOutline, logoGithub, logoGoogle, phonePortraitOutline } from "ionicons/icons"
import type { NativeBridge } from "../bridge/types"

export function LoginPage({
  bridge,
}: {
  bridge: NativeBridge
  onLogin: () => void
}) {
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
      setErrorMessage("Please enter an 11-digit phone number")
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
        error instanceof Error ? error.message : "Failed to send code",
      )
    } finally {
      setLoadingProvider(null)
    }
  }

  const handlePhoneLogin = async () => {
    if (code.length < 4) {
      setErrorMessage("Please enter the verification code")
      return
    }
    setErrorMessage(null)
    setLoadingProvider("phone-login")
    try {
      await bridge.request("auth", "phone.verifyCode", { phone, code })
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : "Verification failed",
      )
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
        error instanceof Error ? error.message : "Could not open browser.",
      )
      setLoadingProvider(null)
    }
  }

  return (
    <IonPage>
      <IonContent className="ion-padding">
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            minHeight: "100%",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: 56,
              height: 56,
              borderRadius: 16,
              backgroundColor: "var(--ion-color-primary)",
              marginBottom: 16,
            }}
          >
            <IonIcon
              icon={terminalOutline}
              style={{ fontSize: 28, color: "#fff" }}
            />
          </div>
          <h1 style={{ fontSize: 24, fontWeight: 700, margin: 0 }}>
            CortexTerminal
          </h1>
          <p
            style={{
              color: "var(--ion-color-medium)",
              fontSize: 14,
              marginBottom: 32,
            }}
          >
            Sign in to continue
          </p>

          {/* Phone number login */}
          <div style={{ width: "100%", maxWidth: 400, marginBottom: 24 }}>
            <IonInput
              type="tel"
              maxlength={11}
              placeholder="Phone number"
              value={phone}
              onIonInput={(e) => setPhone((e.detail.value ?? "").replace(/\D/g, ""))}
              disabled={loadingProvider !== null}
              style={{
                "--padding-start": "12px",
                border: "1px solid var(--ion-color-medium)",
                borderRadius: 8,
                marginBottom: 8,
                height: 44,
              }}
            >
              <div
                slot="start"
                style={{
                  paddingRight: 8,
                  borderRight: "1px solid var(--ion-color-medium)",
                  marginRight: 8,
                  color: "var(--ion-color-medium)",
                  fontSize: 14,
                }}
              >
                +86
              </div>
            </IonInput>

            <div style={{ display: "flex", gap: 8 }}>
              <IonInput
                type="number"
                maxlength={6}
                placeholder="Verification code"
                value={code}
                onIonInput={(e) => setCode((e.detail.value ?? "").replace(/\D/g, ""))}
                disabled={loadingProvider !== null || !codeSent}
                style={{
                  "--padding-start": "12px",
                  border: "1px solid var(--ion-color-medium)",
                  borderRadius: 8,
                  flex: 1,
                  height: 44,
                }}
              />
              <IonButton
                fill="outline"
                onClick={handleSendCode}
                disabled={loadingProvider !== null || countdown > 0 || phone.length !== 11}
                style={{ height: 44, margin: 0 }}
              >
                {loadingProvider === "phone" ? (
                  <IonSpinner name="crescent" />
                ) : countdown > 0 ? (
                  `${countdown}s`
                ) : codeSent ? (
                  "Resend"
                ) : (
                  "Get Code"
                )}
              </IonButton>
            </div>

            {codeSent && (
              <IonButton
                expand="block"
                onClick={handlePhoneLogin}
                disabled={loadingProvider !== null || code.length < 4}
                style={{ marginTop: 12, height: 44 }}
              >
                {loadingProvider === "phone-login" ? (
                  <IonSpinner name="crescent" />
                ) : (
                  <>
                    <IonIcon slot="start" icon={phonePortraitOutline} style={{ fontSize: 20 }} />
                    Login
                  </>
                )}
              </IonButton>
            )}
          </div>

          {/* Divider */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              width: "100%",
              maxWidth: 400,
              marginBottom: 16,
            }}
          >
            <div
              style={{
                flex: 1,
                height: 1,
                backgroundColor: "var(--ion-color-medium)",
              }}
            />
            <span
              style={{
                padding: "0 16px",
                color: "var(--ion-color-medium)",
                fontSize: 13,
              }}
            >
              or sign in with
            </span>
            <div
              style={{
                flex: 1,
                height: 1,
                backgroundColor: "var(--ion-color-medium)",
              }}
            />
          </div>

          {/* OAuth buttons */}
          <div style={{ width: "100%", maxWidth: 400 }}>
            <IonButton
              expand="block"
              fill="outline"
              onClick={() => handleOAuth("apple")}
              disabled={loadingProvider !== null}
              style={{ marginBottom: 12 }}
            >
              {loadingProvider === "apple" ? (
                <IonSpinner name="crescent" />
              ) : (
                <span style={{ fontWeight: 600 }}> Sign in with Apple</span>
              )}
            </IonButton>
            <IonButton
              expand="block"
              fill="outline"
              onClick={() => handleOAuth("github")}
              disabled={loadingProvider !== null}
              style={{ marginBottom: 12 }}
            >
              {loadingProvider === "github" ? (
                <IonSpinner name="crescent" />
              ) : (
                <>
                  <IonIcon slot="start" icon={logoGithub} style={{ fontSize: 20 }} />
                  Continue with GitHub
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
                  <IonIcon slot="start" icon={logoGoogle} style={{ fontSize: 20 }} />
                  Continue with Google
                </>
              )}
            </IonButton>
          </div>

          {errorMessage && (
            <IonText color="danger">
              <p style={{ fontSize: 13, marginTop: 16 }}>{errorMessage}</p>
            </IonText>
          )}
        </div>
      </IonContent>
    </IonPage>
  )
}
