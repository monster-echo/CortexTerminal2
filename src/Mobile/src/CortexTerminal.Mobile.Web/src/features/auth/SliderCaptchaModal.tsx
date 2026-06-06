import { useState, useRef, useCallback, useEffect } from "react";
import { IonModal, IonHeader, IonToolbar, IonTitle, IonContent, IonText, IonSpinner, IonButton } from "@ionic/react";
import { useTranslation } from "react-i18next";
import { authBridge } from "../../bridge/modules/authBridge";

interface SliderCaptchaModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: (captchaToken: string) => void;
}

interface CaptchaChallenge {
  id: string;
  backgroundImage: string;
  sliderImage: string;
  y: number;
}

const IMAGE_WIDTH = 300;
const PIECE_SIZE = 44;

type FeedbackState = "idle" | "success" | "failed";

const shakeKeyframes = `
@keyframes captchaShake {
  0%, 100% { transform: translateX(0); }
  20% { transform: translateX(-6px); }
  40% { transform: translateX(6px); }
  60% { transform: translateX(-4px); }
  80% { transform: translateX(4px); }
}`;

export function SliderCaptchaModal({ isOpen, onClose, onSuccess }: SliderCaptchaModalProps) {
  const { t } = useTranslation();
  const [challenge, setChallenge] = useState<CaptchaChallenge | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState(false);
  const [sliderX, setSliderX] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [verifying, setVerifying] = useState(false);
  const [feedback, setFeedback] = useState<FeedbackState>("idle");
  const [shaking, setShaking] = useState(false);
  const dragStartX = useRef(0);
  const sliderStartX = useRef(0);

  const loadChallenge = useCallback(async () => {
    setFailed(false);
    setLoadError(false);
    setSliderX(0);
    setFeedback("idle");
    setLoading(true);
    try {
      const data = await authBridge.getCaptchaChallenge();
      setChallenge(data);
    } catch {
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (isOpen) loadChallenge();
  }, [isOpen, loadChallenge]);

  // Auto-clear failed feedback after animation
  useEffect(() => {
    if (feedback === "failed") {
      const timer = setTimeout(() => setFeedback("idle"), 1500);
      return () => clearTimeout(timer);
    }
  }, [feedback]);

  const handleDragStart = useCallback(
    (e: React.MouseEvent | React.TouchEvent) => {
      if (verifying || feedback === "success") return;
      e.preventDefault();
      setDragging(true);
      setFeedback("idle");
      const clientX = "touches" in e ? e.touches[0].clientX : e.clientX;
      dragStartX.current = clientX;
      sliderStartX.current = sliderX;
    },
    [verifying, sliderX, feedback]
  );

  useEffect(() => {
    if (!dragging) return;

    const handleMove = (e: MouseEvent | TouchEvent) => {
      const clientX = "touches" in e ? e.touches[0].clientX : e.clientX;
      const delta = clientX - dragStartX.current;
      const maxX = IMAGE_WIDTH - PIECE_SIZE;
      const newX = Math.max(0, Math.min(maxX, sliderStartX.current + delta));
      setSliderX(newX);
    };

    const handleEnd = async () => {
      setDragging(false);
      if (!challenge) return;
      setVerifying(true);
      try {
        const result = await authBridge.verifyCaptcha(challenge.id, Math.round(sliderX));
        if (!result.captchaToken) {
          setFeedback("failed");
          setShaking(true);
          setTimeout(() => setShaking(false), 500);
          setSliderX(0);
          loadChallenge();
          return;
        }
        setFeedback("success");
        setSliderX(IMAGE_WIDTH - PIECE_SIZE);
        setTimeout(() => {
          onSuccess(result.captchaToken!);
          onClose();
        }, 500);
      } catch {
        setFeedback("failed");
        setShaking(true);
        setTimeout(() => setShaking(false), 500);
        setSliderX(0);
        loadChallenge();
      } finally {
        setVerifying(false);
      }
    };

    window.addEventListener("mousemove", handleMove);
    window.addEventListener("mouseup", handleEnd);
    window.addEventListener("touchmove", handleMove, { passive: false });
    window.addEventListener("touchend", handleEnd);
    return () => {
      window.removeEventListener("mousemove", handleMove);
      window.removeEventListener("mouseup", handleEnd);
      window.removeEventListener("touchmove", handleMove);
      window.removeEventListener("touchend", handleEnd);
    };
  }, [dragging, challenge, sliderX, onSuccess, onClose, loadChallenge]);

  function setFailed(_: boolean) { setFeedback("idle"); }

  const trackBorderColor =
    feedback === "success" ? "var(--ion-color-success)" :
    feedback === "failed" ? "var(--ion-color-danger)" :
    "transparent";

  const trackBg =
    feedback === "success" ? "rgba(var(--ion-color-success-rgb), 0.15)" :
    feedback === "failed" ? "rgba(var(--ion-color-danger-rgb), 0.1)" :
    "var(--ion-color-light)";

  const fillBg =
    feedback === "success" ? "rgba(var(--ion-color-success-rgb), 0.3)" :
    feedback === "failed" ? "rgba(var(--ion-color-danger-rgb), 0.3)" :
    "rgba(var(--ion-color-primary-rgb), 0.2)";

  const handleBorder =
    feedback === "success" ? "var(--ion-color-success)" :
    feedback === "failed" ? "var(--ion-color-danger)" :
    "var(--ion-color-primary)";

  return (
    <IonModal isOpen={isOpen} onDidDismiss={onClose}>
      <IonHeader>
        <IonToolbar>
          <IonTitle>{t("login.verificationRequired")}</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent className="ion-padding">
        <style>{shakeKeyframes}</style>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 16, paddingTop: 16 }}>
          {/* Captcha image area */}
          <div
            style={{
              position: "relative",
              width: IMAGE_WIDTH,
              height: 180,
              overflow: "hidden",
              borderRadius: 8,
              border: "1px solid var(--ion-color-light-shade)",
              userSelect: "none",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: "var(--ion-color-light)",
            }}
          >
            {loading && (
              <IonSpinner name="crescent" />
            )}
            {loadError && !loading && (
              <IonButton fill="clear" onClick={loadChallenge}>
                {t("login.captchaRetry")}
              </IonButton>
            )}
            {challenge && !loading && !loadError && (
              <>
                <img
                  src={`data:image/png;base64,${challenge.backgroundImage}`}
                  alt=""
                  draggable={false}
                  width={IMAGE_WIDTH}
                  height={180}
                  style={{ display: "block", position: "absolute", top: 0, left: 0 }}
                />
                <img
                  src={`data:image/png;base64,${challenge.sliderImage}`}
                  alt=""
                  draggable={false}
                  width={IMAGE_WIDTH}
                  height={180}
                  style={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    display: "block",
                    transform: `translateX(${sliderX}px)`,
                  }}
                />
              </>
            )}
          </div>

          {/* Slider track */}
          <div
            style={{
              position: "relative",
              height: 44,
              width: IMAGE_WIDTH,
              borderRadius: 22,
              background: trackBg,
              border: `2px solid ${trackBorderColor}`,
              transition: "background 0.3s, border-color 0.3s",
            }}
          >
            {/* Filled portion */}
            <div
              style={{
                position: "absolute",
                top: 0,
                bottom: 0,
                left: 0,
                borderRadius: 22,
                background: fillBg,
                width: sliderX + PIECE_SIZE,
                transition: "background 0.3s",
              }}
            />
            {/* Draggable handle */}
            <div
              onMouseDown={handleDragStart}
              onTouchStart={handleDragStart}
              style={{
                position: "absolute",
                top: 0,
                left: sliderX,
                width: 44,
                height: 44,
                borderRadius: "50%",
                border: `2px solid ${handleBorder}`,
                background: "var(--ion-background-color)",
                boxShadow: "0 2px 6px rgba(0,0,0,0.15)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                cursor: verifying ? "not-allowed" : dragging ? "grabbing" : "grab",
                opacity: verifying ? 0.6 : 1,
                transition: "border-color 0.3s, opacity 0.2s",
                animation: shaking ? "captchaShake 0.4s ease" : "none",
              }}
            >
              {feedback === "success" ? (
                <svg width="20" height="20" viewBox="0 0 20 20" fill="none" style={{ color: "var(--ion-color-success)" }}>
                  <path d="M5 10l3 3 7-7" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              ) : (
                <svg width="20" height="20" viewBox="0 0 20 20" fill="none" style={{ color: handleBorder }}>
                  <path d="M7 4l-4 6 4 6M13 4l4 6-4 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </div>
          </div>

          {/* Status text */}
          {feedback === "failed" && (
            <IonText color="danger">
              <p style={{ fontSize: 14, fontWeight: 500 }}>{t("login.captchaFailed")}</p>
            </IonText>
          )}
          {feedback === "success" && (
            <IonText color="success">
              <p style={{ fontSize: 14, fontWeight: 500 }}>{t("login.captchaSuccess")}</p>
            </IonText>
          )}
          {verifying && (
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <IonSpinner name="crescent" style={{ width: 16, height: 16 }} />
              <IonText color="medium">
                <p style={{ fontSize: 14 }}>{t("login.captchaVerifying")}</p>
              </IonText>
            </div>
          )}
        </div>
      </IonContent>
    </IonModal>
  );
}
