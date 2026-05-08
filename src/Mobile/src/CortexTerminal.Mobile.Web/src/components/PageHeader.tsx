import { IonHeader, IonToolbar, IonButtons, IonMenuButton, IonBackButton, IonTitle } from "@ionic/react";

interface PageHeaderProps {
  title: string;
  defaultHref?: string;
}

export default function PageHeader({ title, defaultHref }: PageHeaderProps) {
  return (
    <IonHeader translucent>
      <IonToolbar>
        <IonButtons slot="start">
          {defaultHref ? (
            <IonBackButton defaultHref={defaultHref} />
          ) : (
            <IonMenuButton />
          )}
        </IonButtons>
        <IonTitle>{title}</IonTitle>
      </IonToolbar>
    </IonHeader>
  );
}
