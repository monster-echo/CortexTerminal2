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
import ActionResultCard from "../../components/ActionResultCard";
import MediaPreviewCard from "../../components/MediaPreviewCard";
import { useAppStore, type AppStoreState } from "../../store/appStore";

const selectBridgeCapabilities = (s: AppStoreState) => s.bridgeCapabilities;

function formatAsset(asset: NativeMediaAsset) {
  const sizeMb = Math.max(asset.fileSizeBytes / (1024 * 1024), 0).toFixed(2);
  return `${asset.fileName} · ${asset.contentType} · ${sizeMb} MB`;
}

export default function VideoFeaturePage() {
  const { t } = useTranslation();
  const bridgeCapabilities = useAppStore(selectBridgeCapabilities);
  const [previewAsset, setPreviewAsset] = useState<NativeMediaAsset | null>(
    null,
  );
  const [resultTitle, setResultTitle] = useState(t("video.initialTitle"));
  const [resultDetail, setResultDetail] = useState(
    t("video.initialDetail"),
  );

  const handleResult = (title: string, asset: NativeMediaAsset | null) => {
    setResultTitle(title);
    setResultDetail(asset ? formatAsset(asset) : t("video.cancelled"));
    if (asset) {
      setPreviewAsset(asset);
    }
    return asset;
  };

  const pickVideo = async () => {
    try {
      const asset = await nativeBridge.pickVideo();
      return handleResult(t("video.pickResult"), asset);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(t("video.pickResult"));
      setResultDetail(`${t("video.errorPrefix")}${message}`);
      return null;
    }
  };

  const captureVideo = async () => {
    try {
      const asset = await nativeBridge.captureVideo();
      return handleResult(t("video.captureResult"), asset);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(t("video.captureResult"));
      setResultDetail(`${t("video.errorPrefix")}${message}`);
      return null;
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("video.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("video.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>
              {t("video.cardSubtitle")}
            </IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {t("video.videoLibrarySupport")}{bridgeCapabilities?.videoLibrary ? t("video.yes") : t("video.no")}
            <br />
            {t("video.videoCaptureSupport")}{bridgeCapabilities?.videoCapture ? t("video.yes") : t("video.no")}
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("video.section")}</IonLabel>
          </IonListHeader>
          <IonItem button detail onClick={() => void pickVideo()}>
            <IonLabel>
              <h2>{t("video.pickVideo")}</h2>
              <p>{t("video.pickVideoDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem button detail onClick={() => void captureVideo()}>
            <IonLabel>
              <h2>{t("video.captureVideo")}</h2>
              <p>{t("video.captureVideoDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void (async () => {
                const asset = await pickVideo();
                if (asset) {
                  await nativeBridge.setStringValue(
                    "template.video.last",
                    formatAsset(asset),
                  );
                  setResultTitle(t("video.cacheResult"));
                  setResultDetail(`${t("video.cached")}${formatAsset(asset)}`);
                }
              })()
            }
          >
            <IonLabel>
              <h2>{t("video.cacheAction")}</h2>
              <p>{t("video.cacheActionDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void (async () => {
                const cached = await nativeBridge.getStringValue(
                  "template.video.last",
                );
                setResultTitle(t("video.lastCache"));
                setResultDetail(cached || t("video.noCache"));
              })()
            }
          >
            <IonLabel>
              <h2>{t("video.readCache")}</h2>
              <p>{t("video.readCacheDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <MediaPreviewCard
          asset={previewAsset}
          emptyTitle={t("video.noPreviewTitle")}
          emptyDetail={t("video.noPreviewDetail")}
        />

        <ActionResultCard
          title={resultTitle}
          detail={resultDetail}
          note={t("video.note")}
        />
      </IonContent>
    </IonPage>
  );
}
