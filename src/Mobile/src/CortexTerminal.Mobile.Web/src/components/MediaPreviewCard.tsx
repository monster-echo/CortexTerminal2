import {
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonCardTitle,
  IonNote,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import type { NativeMediaAsset } from "../bridge/nativeBridge";
import "./MediaPreviewCard.css";

export interface MediaPreviewCardProps {
  asset: NativeMediaAsset | null;
  emptyTitle?: string;
  emptyDetail?: string;
}

function isImage(asset: NativeMediaAsset) {
  return asset.contentType.startsWith("image/");
}

function isVideo(asset: NativeMediaAsset) {
  return asset.contentType.startsWith("video/");
}

export default function MediaPreviewCard({
  asset,
  emptyTitle,
  emptyDetail,
}: MediaPreviewCardProps) {
  const { t } = useTranslation();

  return (
    <IonCard>
      <IonCardHeader>
        <IonCardTitle>{asset ? t("components.mediaPreviewTitle") : (emptyTitle ?? t("components.mediaPreviewEmptyTitle"))}</IonCardTitle>
        <IonCardSubtitle>
          {asset ? asset.fileName : t("components.mediaPreviewSubtitle")}
        </IonCardSubtitle>
      </IonCardHeader>
      <IonCardContent>
        {!asset ? <p>{emptyDetail ?? t("components.mediaPreviewEmptyDetail")}</p> : null}
        {asset?.localUrl && isImage(asset) ? (
          <img
            src={asset.localUrl}
            alt={asset.fileName}
            className="media-preview-card__asset"
          />
        ) : null}
        {asset?.localUrl && isVideo(asset) ? (
          <video
            src={asset.localUrl}
            controls
            playsInline
            preload="metadata"
            className="media-preview-card__asset"
          />
        ) : null}
        {asset ? (
          <p className="media-preview-card__note">
            <IonNote color="medium">
              {t("components.mediaSource")}{asset.source}
              {asset.localUrl ? t("components.mediaCached") : ""}
            </IonNote>
          </p>
        ) : null}
      </IonCardContent>
    </IonCard>
  );
}
