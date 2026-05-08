import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonChip,
  IonIcon,
  IonInput,
  IonButton,
  IonAvatar,
  useIonToast,
} from "@ionic/react";
import { closeCircle, star, heart } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function ChipDemoPage() {
  const { t } = useTranslation();
  const [presentToast] = useIonToast();
  const [chips, setChips] = useState<string[]>([
    t("demos.chip.basic"),
    t("demos.chip.outline"),
    t("demos.chip.icon"),
  ]);
  const [newChip, setNewChip] = useState("");

  const handleRemove = (index: number) => {
    const removed = chips[index];
    setChips((prev) => prev.filter((_, i) => i !== index));
    presentToast({
      message: `${t("demos.chip.removed")}${removed}`,
      duration: 1000,
      position: "bottom",
    });
  };

  const handleAdd = () => {
    if (newChip.trim()) {
      setChips((prev) => [...prev, newChip.trim()]);
      presentToast({
        message: `${t("demos.chip.added")}${newChip.trim()}`,
        duration: 1000,
        position: "bottom",
      });
      setNewChip("");
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.chip.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.chip.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItem>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8, padding: "4px 0" }}>
              {chips.map((chip, index) => (
                <IonChip key={index}>
                  <IonLabel>{chip}</IonLabel>
                  <IonIcon
                    icon={closeCircle}
                    onClick={() => handleRemove(index)}
                    style={{ cursor: "pointer" }}
                  />
                </IonChip>
              ))}
            </div>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">{t("demos.chip.avatar")}</IonLabel>
          </IonItem>
          <IonItem>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8, padding: "4px 0" }}>
              <IonChip>
                <IonAvatar>
                  <img src="https://ionicframework.com/docs/img/demos/avatar.svg" alt="" />
                </IonAvatar>
                <IonLabel>Avatar</IonLabel>
              </IonChip>
              <IonChip outline>
                <IonIcon icon={star} color="warning" />
                <IonLabel>{t("demos.chip.icon")}</IonLabel>
              </IonChip>
              <IonChip outline>
                <IonIcon icon={heart} color="danger" />
                <IonLabel>Heart</IonLabel>
              </IonChip>
            </div>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItem>
            <IonInput
              placeholder={t("demos.chip.placeholder")}
              value={newChip}
              onIonInput={(e) => setNewChip(e.detail.value ?? "")}
              onKeyDown={(e) => { if (e.key === "Enter") handleAdd(); }}
            />
            <IonButton slot="end" size="default" onClick={handleAdd}>
              {t("demos.chip.add")}
            </IonButton>
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
