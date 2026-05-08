import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonSearchbar,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

const ALL_ITEMS = Array.from({ length: 30 }, (_, i) => `List item ${i + 1}`);

export default function SearchbarDemoPage() {
  const { t } = useTranslation();
  const [searchText, setSearchText] = useState("");

  const filteredItems = ALL_ITEMS.filter((item) =>
    item.toLowerCase().includes(searchText.toLowerCase())
  );

  return (
    <IonPage>
      <PageHeader title={t("demos.searchbar.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.searchbar.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonSearchbar
          placeholder={t("demos.searchbar.placeholder")}
          debounce={300}
          onIonInput={(e) => setSearchText(e.detail.value ?? "")}
        />

        {searchText.length > 0 && (
          <IonItem lines="none">
            <IonLabel color="medium">
              {filteredItems.length > 0
                ? t("demos.searchbar.found", { count: filteredItems.length })
                : t("demos.searchbar.noResult")}
            </IonLabel>
          </IonItem>
        )}

        <IonList>
          {filteredItems.map((item, index) => (
            <IonItem key={index}>
              <IonLabel>{item}</IonLabel>
            </IonItem>
          ))}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
