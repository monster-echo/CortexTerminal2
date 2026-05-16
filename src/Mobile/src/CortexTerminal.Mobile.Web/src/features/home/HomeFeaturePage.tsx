import {
  IonBadge,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonCardTitle,
  IonContent,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonNote,
  IonPage,
} from "@ionic/react";
import {
  cameraOutline,
  chatbubbleEllipsesOutline,
  codeWorkingOutline,
  colorPaletteOutline,
  imageOutline,
  notificationsOutline,
  phonePortraitOutline,
  serverOutline,
  settingsOutline,
  videocamOutline,
} from "ionicons/icons";
import { RouteComponentProps } from "react-router-dom";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { useAppStore, type AppStoreState } from "../../store/appStore";

const selectAppInfo = (s: AppStoreState) => s.appInfo;
const selectLastBridgeError = (s: AppStoreState) => s.lastBridgeError;

export interface HomeFeaturePageProps extends RouteComponentProps<{}> {}

export default function HomeFeaturePage({ history }: HomeFeaturePageProps) {
  const { t } = useTranslation();
  const appInfo = useAppStore(selectAppInfo);
  const lastBridgeError = useAppStore(selectLastBridgeError);
  const featureItems = [
    {
      key: "messages",
      label: t("home.messages"),
      description: t("home.messagesDesc"),
      icon: chatbubbleEllipsesOutline,
      route: "/messages",
    },
    {
      key: "notifications",
      label: t("home.notifications"),
      description: t("home.notificationsDesc"),
      icon: notificationsOutline,
      route: "/notifications",
    },
    {
      key: "haptics",
      label: t("home.haptics"),
      description: t("home.hapticsDesc"),
      icon: phonePortraitOutline,
      route: "/haptics",
    },
    {
      key: "photos",
      label: t("home.photos"),
      description: t("home.photosDesc"),
      icon: imageOutline,
      route: "/photos",
    },
    {
      key: "camera",
      label: t("home.camera"),
      description: t("home.cameraDesc"),
      icon: cameraOutline,
      route: "/camera",
    },
    {
      key: "video",
      label: t("home.video"),
      description: t("home.videoDesc"),
      icon: videocamOutline,
      route: "/video",
    },
    {
      key: "bridge",
      label: t("home.bridge"),
      description: t("home.bridgeDesc"),
      icon: codeWorkingOutline,
      route: "/bridge",
    },
    {
      key: "preferences",
      label: t("home.preferences"),
      description: t("home.preferencesDesc"),
      icon: serverOutline,
      route: "/preferences",
    },
    {
      key: "theme",
      label: t("home.theme"),
      description: t("home.themeDesc"),
      icon: colorPaletteOutline,
      route: "/theme",
    },
    {
      key: "settings",
      label: t("home.settings"),
      description: t("home.settingsDesc"),
      icon: settingsOutline,
      route: "/settings",
    },
  ];

  return (
    <IonPage>
      <PageHeader title={t("home.title")} />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>
              {appInfo?.appName ?? t("home.appName")}
            </IonCardTitle>
            <IonCardSubtitle>{t("home.subtitle")}</IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {lastBridgeError ? (
              <IonNote
                color="danger"
                style={{ display: "block", marginTop: 12 }}
              >
                {t("home.lastError")}{lastBridgeError}
              </IonNote>
            ) : null}
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("home.featureList")}</IonLabel>
          </IonListHeader>
          {featureItems.map((item) => (
            <IonItem
              key={item.key}
              button
              detail
              onClick={() => history.push(item.route)}
            >
              <IonIcon slot="start" icon={item.icon} />
              <IonLabel>
                <h2>{item.label}</h2>
                <p>{item.description}</p>
              </IonLabel>
            </IonItem>
          ))}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
