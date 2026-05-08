import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonButton,
  IonList,
  IonItem,
  IonLabel,
  IonInput,
  IonModal,
  IonListHeader,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function ModalDemoPage() {
  const { t } = useTranslation();
  const [isOpen, setIsOpen] = useState(false);
  const [isSheetOpen, setIsSheetOpen] = useState(false);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [result, setResult] = useState("");

  const handleSubmit = () => {
    setResult(`${t("demos.modal.submitted")}${name} (${email})`);
    setIsOpen(false);
    setName("");
    setEmail("");
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.modal.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.modal.title")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.modal.description")}</p>
            </IonLabel>
          </IonItem>
          <IonItem>
            <IonButton expand="block" onClick={() => setIsOpen(true)}>
              {t("demos.modal.open")}
            </IonButton>
          </IonItem>
          <IonItem>
            <IonButton expand="block" fill="outline" onClick={() => setIsSheetOpen(true)}>
              {t("demos.modal.sheetModal")}
            </IonButton>
          </IonItem>
          {result && (
            <IonItem>
              <IonLabel color="primary">{result}</IonLabel>
            </IonItem>
          )}
        </IonList>

        <IonModal isOpen={isOpen} onDidDismiss={() => setIsOpen(false)}>
          <IonContent>
            <IonList>
              <IonListHeader>
                <IonLabel>{t("demos.modal.formTitle")}</IonLabel>
              </IonListHeader>
              <IonItem>
                <IonInput
                  label={t("demos.modal.name")}
                  labelPlacement="stacked"
                  placeholder={t("demos.modal.namePlaceholder")}
                  value={name}
                  onIonInput={(e) => setName(e.detail.value ?? "")}
                />
              </IonItem>
              <IonItem>
                <IonInput
                  label={t("demos.modal.email")}
                  labelPlacement="stacked"
                  placeholder={t("demos.modal.emailPlaceholder")}
                  value={email}
                  onIonInput={(e) => setEmail(e.detail.value ?? "")}
                />
              </IonItem>
              <IonItem>
                <IonButton expand="block" onClick={handleSubmit}>
                  {t("demos.modal.submit")}
                </IonButton>
              </IonItem>
              <IonItem>
                <IonButton expand="block" fill="outline" color="medium" onClick={() => setIsOpen(false)}>
                  {t("demos.modal.cancel")}
                </IonButton>
              </IonItem>
            </IonList>
          </IonContent>
        </IonModal>

        <IonModal
          isOpen={isSheetOpen}
          onDidDismiss={() => setIsSheetOpen(false)}
          breakpoints={[0, 0.5, 1]}
          initialBreakpoint={0.5}
        >
          <IonContent>
            <IonList>
              <IonListHeader>
                <IonLabel>{t("demos.modal.formTitle")}</IonLabel>
              </IonListHeader>
              <IonItem>
                <IonInput
                  label={t("demos.modal.name")}
                  labelPlacement="stacked"
                  placeholder={t("demos.modal.namePlaceholder")}
                  value={name}
                  onIonInput={(e) => setName(e.detail.value ?? "")}
                />
              </IonItem>
              <IonItem>
                <IonInput
                  label={t("demos.modal.email")}
                  labelPlacement="stacked"
                  placeholder={t("demos.modal.emailPlaceholder")}
                  value={email}
                  onIonInput={(e) => setEmail(e.detail.value ?? "")}
                />
              </IonItem>
              <IonItem>
                <IonButton
                  expand="block"
                  onClick={() => {
                    handleSubmit();
                    setIsSheetOpen(false);
                  }}
                >
                  {t("demos.modal.submit")}
                </IonButton>
              </IonItem>
            </IonList>
          </IonContent>
        </IonModal>
      </IonContent>
    </IonPage>
  );
}
