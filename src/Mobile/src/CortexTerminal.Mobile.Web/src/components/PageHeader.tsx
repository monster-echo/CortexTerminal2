import { IonHeader, IonToolbar, IonButtons, IonMenuButton, IonBackButton, IonTitle } from "@ionic/react";
import { useTranslation } from "react-i18next";

interface PageHeaderProps {
  title: string;
  defaultHref?: string;
}

export default function PageHeader({ title, defaultHref }: PageHeaderProps) {
  const { t } = useTranslation();
  return (
    <IonHeader translucent>
      <IonToolbar>
        <IonButtons slot="start">
          {defaultHref ? (
            <IonBackButton defaultHref={defaultHref} text={t("common.back")} />
          ) : (
            <IonMenuButton />
          )}
        </IonButtons>
        <IonTitle>{title}</IonTitle>
      </IonToolbar>
    </IonHeader>
  );
}
