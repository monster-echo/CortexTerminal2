import { useState, useEffect } from "react";
import {
  IonPage,
  IonContent,
  IonCard,
  IonCardHeader,
  IonCardTitle,
  IonCardContent,
  IonButton,
  IonIcon,
  IonText,
  IonSpinner,
  IonList,
  IonItem,
  IonLabel,
  useIonToast,
} from "@ionic/react";
import { warningOutline, mailOutline, chatbubblesOutline, paperPlaneOutline } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import { RouteComponentProps } from "react-router-dom";
import PageHeader from "../../components/PageHeader";
import { supportBridge } from "../../bridge/modules/supportBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import type { SupportInfo, SupportGroup } from "../../schemas/bridgeSchema";

export default function ContactSupportPage(_: RouteComponentProps) {
  const { t } = useTranslation();
  const [presentToast] = useIonToast();
  const [info, setInfo] = useState<SupportInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      setInfo(await supportBridge.getSupportInfo());
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const copyToClipboard = async (text: string) => {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      void presentToast({ message: t("support.copied"), duration: 1500, position: "bottom", color: "success" });
    } catch {
      void presentToast({ message: t("support.copyFailed"), duration: 1500, position: "bottom", color: "danger" });
    }
  };

  const openLink = (url: string) => {
    if (url) void nativeBridge.openExternalLink(url);
  };

  const renderGroup = (g: SupportGroup, isTelegram: boolean) => {
    const copyValue = isTelegram ? g.url : g.number;
    return (
      <IonCard>
        <IonCardHeader>
          <IonCardTitle>
            <IonIcon
              icon={isTelegram ? paperPlaneOutline : chatbubblesOutline}
              style={{ verticalAlign: "middle", marginRight: 6 }}
            />
            {isTelegram ? g.name : t("support.qqGroupName")}
          </IonCardTitle>
        </IonCardHeader>
        <IonCardContent>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <IonText color="medium" style={{ flex: 1, wordBreak: "break-all" }}>
              {copyValue}
            </IonText>
            <IonButton size="small" fill="outline" onClick={() => void copyToClipboard(copyValue)}>
              {t("support.copy")}
            </IonButton>
          </div>
          {g.qrCodeUrl && (
            <div style={{ textAlign: "center", marginTop: 12 }}>
              <img
                src={g.qrCodeUrl}
                alt="QR"
                onClick={() => setPreviewUrl(g.qrCodeUrl)}
                style={{ width: 160, height: 160, borderRadius: 8, background: "#fff", cursor: "pointer" }}
              />
              <div style={{ marginTop: 6 }}>
                <IonText color="medium" style={{ fontSize: 12 }}>{t("support.scanToJoin")}</IonText>
              </div>
              <IonButton fill="outline" size="small" style={{ marginTop: 8 }} onClick={() => void nativeBridge.saveImageToGallery(g.qrCodeUrl)}>
                {t("support.saveImage")}
              </IonButton>
            </div>
          )}
          {isTelegram && g.url && (
            <IonButton expand="block" style={{ marginTop: 12 }} onClick={() => openLink(g.url)}>
              {t("support.openTelegram")}
            </IonButton>
          )}
        </IonCardContent>
      </IonCard>
    );
  };

  return (
    <IonPage>
      <PageHeader title={t("support.title")} defaultHref="/settings" />
      <IonContent fullscreen>
        {loading && (
          <div style={{ textAlign: "center", padding: 48 }}>
            <IonSpinner name="crescent" />
          </div>
        )}
        {!loading && error && (
          <div style={{ textAlign: "center", padding: 32 }}>
            <IonIcon icon={warningOutline} style={{ fontSize: 48, color: "var(--ion-color-danger)" }} />
            <p style={{ color: "var(--ion-color-medium)" }}>{t("support.loadFailed")}</p>
            <p style={{ color: "var(--ion-color-medium)", fontSize: 12 }}>{error}</p>
            <IonButton fill="outline" onClick={() => void load()} style={{ marginTop: 8 }}>
              {t("support.retry")}
            </IonButton>
          </div>
        )}
        {!loading && !error && info && (
          <>
            {info.qqGroup && renderGroup(info.qqGroup, false)}
            {info.telegramGroup && renderGroup(info.telegramGroup, true)}
            {info.email && (
              <IonList inset>
                <IonItem button onClick={() => void nativeBridge.composeSupportEmail(t("settings.emailSubject"), t("settings.emailBody"), info.email)}>
                  <IonIcon slot="start" icon={mailOutline} />
                  <IonLabel>{info.email}</IonLabel>
                </IonItem>
              </IonList>
            )}
          </>
        )}
        {previewUrl && (
          <div
            onClick={() => setPreviewUrl(null)}
            style={{ position: "fixed", inset: 0, background: "#000", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 9999 }}
          >
            <img src={previewUrl} alt="QR" style={{ maxWidth: "100%", maxHeight: "100%", objectFit: "contain" }} />
            <IonButton
              fill="outline"
              color="light"
              onClick={(e) => { e.stopPropagation(); void nativeBridge.saveImageToGallery(previewUrl); }}
              style={{ position: "absolute", bottom: 48, right: 24 }}
            >
              {t("support.saveImage")}
            </IonButton>
          </div>
        )}
      </IonContent>
    </IonPage>
  );
}
