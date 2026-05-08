import { useState, useRef, useCallback } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonProgressBar,
  IonButton,
  IonListHeader,
  IonSkeletonText,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function ProgressDemoPage() {
  const { t } = useTranslation();
  const [progress, setProgress] = useState(0);
  const [running, setRunning] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const handleStart = useCallback(() => {
    if (running) return;
    setRunning(true);
    setProgress(0);
    intervalRef.current = setInterval(() => {
      setProgress((prev) => {
        if (prev >= 1) {
          if (intervalRef.current) clearInterval(intervalRef.current);
          setRunning(false);
          return 1;
        }
        return prev + 0.02;
      });
    }, 100);
  }, [running]);

  const handleReset = useCallback(() => {
    if (intervalRef.current) clearInterval(intervalRef.current);
    setRunning(false);
    setProgress(0);
  }, []);

  return (
    <IonPage>
      <PageHeader title={t("demos.progress.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.progress.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.progress.determinate")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonLabel>
              {t("demos.progress.percent", { value: Math.round(progress * 100) })}
            </IonLabel>
          </IonItem>
          <IonProgressBar value={progress} style={{ margin: "0 16px" }} />
          <IonItem>
            <IonButton expand="block" onClick={handleStart} disabled={running}>
              {t("demos.progress.start")}
            </IonButton>
          </IonItem>
          <IonItem>
            <IonButton expand="block" fill="outline" onClick={handleReset}>
              {t("demos.progress.reset")}
            </IonButton>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.progress.indeterminate")}</IonLabel>
          </IonListHeader>
          <IonProgressBar type="indeterminate" style={{ margin: "0 16px" }} />
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.progress.skeleton")}</IonLabel>
          </IonListHeader>
          {[1, 2, 3].map((i) => (
            <IonItem key={i}>
              <IonSkeletonText animated style={{ width: "100%", height: "16px" }} />
            </IonItem>
          ))}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
