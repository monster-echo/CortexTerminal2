import { useState, useEffect, useRef } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonItemDivider,
  IonLabel,
  IonIcon,
  IonModal,
  IonButton,
  IonInput,
  IonText,
  IonNote,
  useIonToast,
  useIonAlert,
} from "@ionic/react";
import {
  lockClosedOutline,
  trashOutline,
} from "ionicons/icons";
import { useTranslation } from "react-i18next";
import { RouteComponentProps } from "react-router-dom";
import PageHeader from "../../components/PageHeader";
import { useAuthStore, type AuthState } from "../../store/authStore";
import { authBridge } from "../../bridge/modules/authBridge";

const selectUser = (s: AuthState) => s.user;
const selectClearSession = (s: AuthState) => s.clearSession;

export default function AccountSecurityPage({ history }: RouteComponentProps) {
  const { t } = useTranslation();
  const user = useAuthStore(selectUser);
  const clearSession = useAuthStore(selectClearSession);
  const [presentToast] = useIonToast();
  const [presentAlert] = useIonAlert();

  const [hasPassword, setHasPassword] = useState<boolean | null>(null);
  const [showPasswordModal, setShowPasswordModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);

  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordSubmitting, setPasswordSubmitting] = useState(false);

  const [deleteIdentity, setDeleteIdentity] = useState("");
  const [deleteSubmitting, setDeleteSubmitting] = useState(false);

  const passwordModalRef = useRef<HTMLIonModalElement>(null);
  const deleteModalRef = useRef<HTMLIonModalElement>(null);

  useEffect(() => {
    authBridge.getProfile().then((profile) => {
      if (profile) {
        setHasPassword(profile.hasPassword);
      }
    }).catch(() => {});
  }, []);

  const resetPasswordForm = () => {
    setCurrentPassword("");
    setNewPassword("");
    setConfirmPassword("");
    setPasswordSubmitting(false);
  };

  const resetDeleteForm = () => {
    setDeleteIdentity("");
    setDeleteSubmitting(false);
  };

  const handleSubmitPassword = async () => {
    if (!newPassword || !confirmPassword) {
      void presentToast({ message: t("settings.passwordEmpty"), duration: 2000, position: "bottom", color: "warning" });
      return;
    }
    if (newPassword !== confirmPassword) {
      void presentToast({ message: t("settings.passwordMismatch"), duration: 2000, position: "bottom", color: "warning" });
      return;
    }
    setPasswordSubmitting(true);
    try {
      await authBridge.setPassword(hasPassword ? currentPassword || null : null, newPassword);
      setHasPassword(true);
      void presentToast({ message: hasPassword ? t("settings.passwordChanged") : t("settings.passwordSet"), duration: 2000, position: "bottom", color: "success" });
      passwordModalRef.current?.dismiss();
      resetPasswordForm();
    } catch (e) {
      void presentToast({ message: (e instanceof Error ? e.message : String(e)) || t("settings.passwordError"), duration: 3000, position: "bottom", color: "danger" });
    } finally {
      setPasswordSubmitting(false);
    }
  };

  const handleConfirmDelete = () => {
    const input = deleteIdentity.trim().toLowerCase();
    const username = (user?.username ?? "").toLowerCase();
    if (!input || (input !== username)) {
      void presentToast({ message: t("settings.deleteAccountUsernameMismatch"), duration: 2000, position: "bottom", color: "danger" });
      return;
    }

    presentAlert({
      header: t("settings.deleteAccountConfirmTitle"),
      message: t("settings.deleteAccountConfirmMessage"),
      buttons: [
        { text: t("settings.cancel"), role: "cancel" },
        {
          text: t("settings.deleteAccountConfirm"),
          role: "destructive",
          handler: () => void performDelete(),
        },
      ],
    });
  };

  const performDelete = async () => {
    setDeleteSubmitting(true);
    try {
      await authBridge.deleteAccount();
      deleteModalRef.current?.dismiss();
      resetDeleteForm();
      void presentToast({ message: t("settings.deleteAccountSuccess"), duration: 2000, position: "bottom", color: "success" });
      clearSession();
      history.replace("/sessions");
    } catch (e) {
      void presentToast({ message: (e instanceof Error ? e.message : String(e)) || t("settings.deleteAccountError"), duration: 3000, position: "bottom", color: "danger" });
    } finally {
      setDeleteSubmitting(false);
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("settings.securitySection")} defaultHref="/settings" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItemDivider>
            <IonLabel className="py-2">{t("settings.securitySection")}</IonLabel>
          </IonItemDivider>
          <IonItem button onClick={() => setShowPasswordModal(true)}>
            <IonIcon slot="start" icon={lockClosedOutline} />
            <IonLabel>
              {hasPassword ? t("settings.changePassword") : t("settings.setPassword")}
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItem button onClick={() => setShowDeleteModal(true)} detail={false}>
            <IonIcon slot="start" icon={trashOutline} color="danger" />
            <IonLabel color="danger">{t("settings.deleteAccount")}</IonLabel>
          </IonItem>
        </IonList>

        {/* Change Password Modal */}
        <IonModal
          ref={passwordModalRef}
          isOpen={showPasswordModal}
          onDidDismiss={() => { setShowPasswordModal(false); resetPasswordForm(); }}
          breakpoints={[0, 0.5, 0.667, 1]}
          initialBreakpoint={0.667}
          handle={true}
        >
          <IonContent fullscreen className="ion-padding">
            <div style={{ maxWidth: 400, margin: "0 auto", paddingTop: 16 }}>
              <IonText>
                <h2>{hasPassword ? t("settings.changePasswordTitle") : t("settings.setPasswordTitle")}</h2>
              </IonText>

              <IonList lines="none" style={{ background: "transparent" }}>
                {hasPassword && (
                  <IonItem style={{ "--padding-top": 8, "--padding-bottom": 8, "--background": "transparent" }}>
                    <IonInput
                      type="password"
                      placeholder={t("settings.currentPassword")}
                      value={currentPassword}
                      onIonInput={(e) => setCurrentPassword(e.detail.value ?? "")}
                      disabled={passwordSubmitting}
                    />
                  </IonItem>
                )}
                <IonItem style={{ "--padding-top": 8, "--padding-bottom": 8, "--background": "transparent" }}>
                  <IonInput
                    type="password"
                    placeholder={t("settings.newPassword")}
                    value={newPassword}
                    onIonInput={(e) => setNewPassword(e.detail.value ?? "")}
                    disabled={passwordSubmitting}
                  />
                </IonItem>
                <IonItem style={{ "--padding-top": 8, "--padding-bottom": 8, "--background": "transparent" }}>
                  <IonInput
                    type="password"
                    placeholder={t("settings.confirmPassword")}
                    value={confirmPassword}
                    onIonInput={(e) => setConfirmPassword(e.detail.value ?? "")}
                    disabled={passwordSubmitting}
                    onKeyDown={(e) => { if (e.key === "Enter") handleSubmitPassword(); }}
                  />
                </IonItem>
              </IonList>

              <div style={{ padding: "0 16px" }}>
                <IonButton
                  expand="block"
                  onClick={handleSubmitPassword}
                  disabled={passwordSubmitting}
                >
                  {passwordSubmitting ? t("settings.cancel") : (hasPassword ? t("settings.changePassword") : t("settings.setPassword"))}
                </IonButton>
                <IonButton
                  expand="block"
                  fill="clear"
                  onClick={() => passwordModalRef.current?.dismiss()}
                  disabled={passwordSubmitting}
                >
                  {t("settings.cancel")}
                </IonButton>
              </div>
            </div>
          </IonContent>
        </IonModal>

        {/* Delete Account Modal */}
        <IonModal
          ref={deleteModalRef}
          isOpen={showDeleteModal}
          onDidDismiss={() => { setShowDeleteModal(false); resetDeleteForm(); }}
          breakpoints={[0, 0.5, 0.667, 1]}
          initialBreakpoint={0.667}
          handle={true}
        >
          <IonContent fullscreen className="ion-padding">
            <div style={{ maxWidth: 400, margin: "0 auto", paddingTop: 16 }}>
              <IonText>
                <h2>{t("settings.deleteAccountConfirmTitle")}</h2>
              </IonText>
              <IonText color="medium">
                <p>{t("settings.deleteAccountConfirmMessage")}</p>
              </IonText>

              <div style={{ padding: "8px 0 12px" }}>
                <IonNote>
                  {t("settings.deleteAccountIdentityLabel")}: <strong>{user?.username}</strong>
                </IonNote>
              </div>

              <IonList lines="none" style={{ background: "transparent" }}>
                <IonItem style={{ "--padding-top": 8, "--padding-bottom": 8, "--background": "transparent" }}>
                  <IonInput
                    type="text"
                    placeholder={t("settings.deleteAccountUsernameHint")}
                    value={deleteIdentity}
                    onIonInput={(e) => setDeleteIdentity(e.detail.value ?? "")}
                    disabled={deleteSubmitting}
                  />
                </IonItem>
              </IonList>

              <div style={{ padding: "0 16px" }}>
                <IonButton
                  expand="block"
                  color="danger"
                  onClick={handleConfirmDelete}
                  disabled={deleteSubmitting || !deleteIdentity.trim()}
                >
                  {t("settings.deleteAccountConfirm")}
                </IonButton>
                <IonButton
                  expand="block"
                  fill="clear"
                  onClick={() => deleteModalRef.current?.dismiss()}
                  disabled={deleteSubmitting}
                >
                  {t("settings.cancel")}
                </IonButton>
              </div>
            </div>
          </IonContent>
        </IonModal>
      </IonContent>
    </IonPage>
  );
}
