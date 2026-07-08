import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonIcon,
  IonList,
  IonItem,
  IonLabel,
  IonSelect,
  IonSelectOption,
  IonTextarea,
  IonInput,
  IonButton,
  IonSpinner,
  useIonToast,
} from "@ionic/react";
import { addOutline, closeCircle } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import { RouteComponentProps, useHistory } from "react-router-dom";
import PageHeader from "../../components/PageHeader";
import { supportBridge } from "../../bridge/modules/supportBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import { useAuthStore, type AuthState } from "../../store/authStore";
import { useAppStore, type AppStoreState } from "../../store/appStore";

const selectUser = (s: AuthState) => s.user;
const selectLanguage = (s: AppStoreState) => s.language;
const selectAppInfo = (s: AppStoreState) => s.appInfo;

interface SubtypeOption {
  value: string;
  key: string;
}

interface AttachmentItem {
  url: string;
  name: string;
}

export default function FeedbackPage({ location }: RouteComponentProps) {
  const { t } = useTranslation();
  const searchParams = new URLSearchParams(location.search);
  const type = searchParams.get("type") === "report" ? "report" : "feedback";
  const user = useAuthStore(selectUser);
  const language = useAppStore(selectLanguage);
  const appInfo = useAppStore(selectAppInfo);
  const [presentToast] = useIonToast();
  const history = useHistory();

  const subtypeOptions: SubtypeOption[] = type === "report"
    ? [
        { value: "violation", key: "feedback.typeReportViolation" },
        { value: "abuse", key: "feedback.typeReportAbuse" },
        { value: "other", key: "feedback.typeReportOther" },
      ]
    : [
        { value: "suggestion", key: "feedback.typeFeedbackSuggestion" },
        { value: "bug", key: "feedback.typeFeedbackBug" },
        { value: "experience", key: "feedback.typeFeedbackExperience" },
      ];

  const [subtype, setSubtype] = useState(subtypeOptions[0].value);
  const [content, setContent] = useState("");
  const [contact, setContact] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [attachments, setAttachments] = useState<AttachmentItem[]>([]);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handlePickFile = async () => {
    try {
      const result = await supportBridge.pickFile();
      if (!result) return;
      setUploading(true);
      setAttachments((prev) => [...prev, { url: result.imageUrl, name: result.filename }]);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setUploading(false);
    }
  };

  const handleSubmit = async () => {
    const trimmed = content.trim();
    if (trimmed.length < 10) {
      setError(t("feedback.contentTooShort"));
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const result = await supportBridge.submitFeedback(
        type,
        subtype,
        trimmed,
        contact.trim(),
        user?.username ?? "unknown",
        language,
        appInfo?.appVersion ?? "unknown",
        JSON.stringify(attachments.map((a) => a.url)),
      );
      nativeBridge.trackEvent(type === "report" ? "submit_report" : "submit_feedback");
      void presentToast({
        message: `${t("feedback.submitted")} ${result.ticketId}`,
        duration: 3000,
        position: "bottom",
        color: "success",
      });
      history.goBack();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <IonPage>
      <PageHeader
        title={t(type === "report" ? "feedback.titleReport" : "feedback.titleFeedback")}
        defaultHref="/settings"
      />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel slot="start">{t("feedback.typeLabel")}</IonLabel>
            <IonSelect
              value={subtype}
              onIonChange={(e) => setSubtype(e.detail.value)}
              disabled={submitting}
              interface="popover"
            >
              {subtypeOptions.map((o) => (
                <IonSelectOption key={o.value} value={o.value}>{t(o.key)}</IonSelectOption>
              ))}
            </IonSelect>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItem>
            <IonLabel position="stacked">{t("feedback.content")}</IonLabel>
            <IonTextarea
              value={content}
              onIonInput={(e) => setContent(e.detail.value ?? "")}
              rows={5}
              placeholder={t("feedback.contentPlaceholder")}
              disabled={submitting}
            />
          </IonItem>
          <IonItem>
            <IonLabel position="stacked">{t("feedback.contact")}</IonLabel>
            <IonInput
              value={contact}
              onIonInput={(e) => setContact(e.detail.value ?? "")}
              placeholder={t("feedback.contactPlaceholder")}
              disabled={submitting}
            />
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItem lines="none">
            <IonLabel position="stacked">{t("feedback.attachments")}</IonLabel>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginTop: 8 }}>
              {attachments.map((item, idx) => (
                <div key={idx} style={{ position: "relative", maxWidth: 180 }}>
                  <div
                    style={{
                      padding: "6px 30px 6px 10px",
                      background: "var(--ion-color-light)",
                      borderRadius: 8,
                      fontSize: 12,
                      whiteSpace: "nowrap",
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                    }}
                  >
                    {item.name}
                  </div>
                  <IonButton
                    size="small"
                    fill="clear"
                    color="danger"
                    onClick={() => setAttachments((prev) => prev.filter((_, i) => i !== idx))}
                    style={{ position: "absolute", top: -8, right: -8, margin: 0 }}
                  >
                    <IonIcon icon={closeCircle} slot="icon-only" />
                  </IonButton>
                </div>
              ))}
              {attachments.length < 3 && (
                <IonButton
                  fill="outline"
                  onClick={() => void handlePickFile()}
                  disabled={uploading || submitting}
                  style={{ height: 32, margin: 0 }}
                >
                  {uploading ? <IonSpinner name="crescent" /> : <IonIcon icon={addOutline} />}
                </IonButton>
              )}
            </div>
          </IonItem>
        </IonList>

        {error && (
          <div style={{ color: "var(--ion-color-danger)", padding: "8px 16px", fontSize: 13 }}>
            {error}
          </div>
        )}

        <div style={{ padding: "8px 16px" }}>
          <IonButton expand="block" onClick={() => void handleSubmit()} disabled={submitting}>
            {submitting ? <IonSpinner name="crescent" /> : t("feedback.submit")}
          </IonButton>
        </div>
      </IonContent>
    </IonPage>
  );
}
