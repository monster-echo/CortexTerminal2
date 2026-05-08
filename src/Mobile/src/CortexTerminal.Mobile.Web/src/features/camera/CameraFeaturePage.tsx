import {
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonCardTitle,
  IonContent,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonPage,
} from "@ionic/react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { nativeBridge, type NativeMediaAsset } from "../../bridge/nativeBridge";
import { useAppStore } from "../../store/appStore";
import ActionResultCard from "../../components/ActionResultCard";
import MediaPreviewCard from "../../components/MediaPreviewCard";

function formatAsset(asset: NativeMediaAsset) {
  const sizeKb = Math.max(asset.fileSizeBytes / 1024, 0).toFixed(1);
  return `${asset.fileName} · ${asset.contentType} · ${sizeKb} KB`;
}

export default function CameraFeaturePage() {
  const { t } = useTranslation();
  const bridgeCapabilities = useAppStore((state) => state.bridgeCapabilities);
  const [previewAsset, setPreviewAsset] = useState<NativeMediaAsset | null>(
    null,
  );
  const [resultTitle, setResultTitle] = useState(t("camera.initialTitle"));
  const [resultDetail, setResultDetail] =
    useState(t("camera.initialDetail"));

  const capturePhoto = async () => {
    try {
      const asset = await nativeBridge.capturePhoto();
      setResultTitle(t("camera.resultTitle"));
      setResultDetail(asset ? formatAsset(asset) : t("camera.cancelled"));
      if (asset) {
        setPreviewAsset(asset);
      }
      return asset;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(t("camera.resultTitle"));
      setResultDetail(`${t("camera.errorPrefix")}${message}`);
      return null;
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("camera.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("camera.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>{t("camera.cardSubtitle")}</IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {t("camera.cameraSupport")}{bridgeCapabilities?.camera ? t("camera.yes") : t("camera.no")}
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("camera.section")}</IonLabel>
          </IonListHeader>
          <IonItem button detail onClick={() => void capturePhoto()}>
            <IonLabel>
              <h2>{t("camera.capture")}</h2>
              <p>{t("camera.captureDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void (async () => {
                const asset = await capturePhoto();
                if (asset) {
                  await nativeBridge.showToastWithDuration(
                    `${t("camera.toastCaptured")}${asset.fileName}`,
                    "short",
                  );
                }
              })()
            }
          >
            <IonLabel>
              <h2>{t("camera.toastCapture")}</h2>
              <p>{t("camera.toastCaptureDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void (async () => {
                const asset = await capturePhoto();
                if (asset) {
                  await nativeBridge.setStringValue(
                    "template.camera.last",
                    formatAsset(asset),
                  );
                  setResultTitle(t("camera.cacheResult"));
                  setResultDetail(`${t("camera.cached")}${formatAsset(asset)}`);
                }
              })()
            }
          >
            <IonLabel>
              <h2>{t("camera.cacheAction")}</h2>
              <p>{t("camera.cacheActionDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void (async () => {
                const cached = await nativeBridge.getStringValue(
                  "template.camera.last",
                );
                setResultTitle(t("camera.lastCache"));
                setResultDetail(cached || t("camera.noCache"));
              })()
            }
          >
            <IonLabel>
              <h2>{t("camera.readCache")}</h2>
              <p>{t("camera.readCacheDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <MediaPreviewCard
          asset={previewAsset}
          emptyTitle={t("camera.noPreviewTitle")}
          emptyDetail={t("camera.noPreviewDetail")}
        />

        <ActionResultCard
          title={resultTitle}
          detail={resultDetail}
          note={t("camera.note")}
        />
      </IonContent>
    </IonPage>
  );
}
