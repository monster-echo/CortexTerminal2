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

function formatAsset(asset: NativeMediaAsset) {
  const sizeKb = Math.max(asset.fileSizeBytes / 1024, 0).toFixed(1);
  return `${asset.fileName} · ${asset.contentType} · ${sizeKb} KB`;
}

export default function PhotosFeaturePage() {
  const { t } = useTranslation();
  const [previewAsset, setPreviewAsset] = useState<NativeMediaAsset | null>(
    null,
  );
  const [resultTitle, setResultTitle] = useState(t("photos.initialTitle"));
  const [resultDetail, setResultDetail] =
    useState(t("photos.initialDetail"));

  const pickPhoto = async () => {
    try {
      const asset = await nativeBridge.pickPhoto();
      setResultTitle(t("photos.resultTitle"));
      setResultDetail(asset ? formatAsset(asset) : t("photos.cancelled"));
      if (asset) {
        setPreviewAsset(asset);
      }
      return asset;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(t("photos.resultTitle"));
      setResultDetail(`${t("photos.errorPrefix")}${message}`);
      return null;
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("photos.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("photos.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>{t("photos.cardSubtitle")}</IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {t("photos.cardContent")}
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("photos.section")}</IonLabel>
          </IonListHeader>
          <IonItem button detail onClick={() => void pickPhoto()}>
            <IonLabel>
              <h2>{t("photos.pickPhoto")}</h2>
              <p>{t("photos.pickPhotoDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void (async () => {
                const asset = await pickPhoto();
                if (asset) {
                  await nativeBridge.showToastWithDuration(
                    `${t("photos.toastPicked")}${asset.fileName}`,
                    "short",
                  );
                }
              })()
            }
          >
            <IonLabel>
              <h2>{t("photos.toastPick")}</h2>
              <p>{t("photos.toastPickDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void (async () => {
                const asset = await pickPhoto();
                if (asset) {
                  await nativeBridge.setStringValue(
                    "template.photos.last",
                    formatAsset(asset),
                  );
                  setResultTitle(t("photos.cacheResult"));
                  setResultDetail(`${t("photos.cached")}${formatAsset(asset)}`);
                }
              })()
            }
          >
            <IonLabel>
              <h2>{t("photos.cacheAction")}</h2>
              <p>{t("photos.cacheActionDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void (async () => {
                const cached = await nativeBridge.getStringValue(
                  "template.photos.last",
                );
                setResultTitle(t("photos.lastCache"));
                setResultDetail(cached || t("photos.noCache"));
              })()
            }
          >
            <IonLabel>
              <h2>{t("photos.readCache")}</h2>
              <p>{t("photos.readCacheDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <MediaPreviewCard
          asset={previewAsset}
          emptyTitle={t("photos.noPreviewTitle")}
          emptyDetail={t("photos.noPreviewDetail")}
        />

        <ActionResultCard
          title={resultTitle}
          detail={resultDetail}
          note={t("photos.note")}
        />
      </IonContent>
    </IonPage>
  );
}
