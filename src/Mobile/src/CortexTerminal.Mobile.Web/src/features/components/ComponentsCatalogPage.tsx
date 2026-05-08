import {
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
  IonPage,
} from "@ionic/react";
import {
  alertOutline,
  appsOutline,
  bookmarkOutline,
  calendarOutline,
  checkmarkCircleOutline,
  chevronForwardOutline,
  cloudDownloadOutline,
  colorFilterOutline,
  documentTextOutline,
  expandOutline,
  filterOutline,
  gridOutline,
  imagesOutline,
  layersOutline,
  listOutline,
  moveOutline,
  navigateOutline,
  removeCircleOutline,
  reorderFourOutline,
  searchOutline,
  shareOutline,
  snowOutline,
  swapVerticalOutline,
  tabletPortraitOutline,
  toggleOutline,
} from "ionicons/icons";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

const catalogItems = [
  { key: "modal", icon: expandOutline, route: "/components/modal" },
  { key: "popover", icon: chevronForwardOutline, route: "/components/popover" },
  { key: "actionSheet", icon: shareOutline, route: "/components/action-sheet" },
  { key: "alert", icon: alertOutline, route: "/components/alert" },
  { key: "loading", icon: snowOutline, route: "/components/loading" },
  { key: "toast", icon: bookmarkOutline, route: "/components/toast" },
  { key: "accordion", icon: layersOutline, route: "/components/accordion" },
  { key: "fab", icon: shareOutline, route: "/components/fab" },
  { key: "tabs", icon: tabletPortraitOutline, route: "/components/tabs" },
  { key: "nav", icon: navigateOutline, route: "/components/nav" },
  { key: "grid", icon: gridOutline, route: "/components/grid" },
  { key: "segment", icon: filterOutline, route: "/components/segment" },
  { key: "refresher", icon: cloudDownloadOutline, route: "/components/refresher" },
  { key: "infiniteScroll", icon: swapVerticalOutline, route: "/components/infinite-scroll" },
  { key: "searchbar", icon: searchOutline, route: "/components/searchbar" },
  { key: "itemSliding", icon: listOutline, route: "/components/item-sliding" },
  { key: "reorder", icon: reorderFourOutline, route: "/components/reorder" },
  { key: "input", icon: documentTextOutline, route: "/components/input" },
  { key: "textarea", icon: documentTextOutline, route: "/components/textarea" },
  { key: "select", icon: chevronForwardOutline, route: "/components/select" },
  { key: "radioCheckbox", icon: checkmarkCircleOutline, route: "/components/radio-checkbox" },
  { key: "datetime", icon: calendarOutline, route: "/components/datetime" },
  { key: "rangeToggle", icon: toggleOutline, route: "/components/range-toggle" },
  { key: "chip", icon: colorFilterOutline, route: "/components/chip" },
  { key: "progress", icon: removeCircleOutline, route: "/components/progress" },
  { key: "avatarThumbnail", icon: imagesOutline, route: "/components/avatar-thumbnail" },
  { key: "spinner", icon: appsOutline, route: "/components/spinner" },
];

export default function ComponentsCatalogPage() {
  const { t } = useTranslation();

  return (
    <IonPage>
      <PageHeader title={t("demos.catalog.title")} />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("demos.catalog.title")}</IonCardTitle>
            <IonCardSubtitle>{t("demos.catalog.subtitle")}</IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>{t("demos.catalog.description")}</IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.catalog.title")}</IonLabel>
          </IonListHeader>
          {catalogItems.map((item) => (
            <IonItem key={item.key} button detail routerLink={item.route} routerDirection="forward">
              <IonIcon slot="start" icon={item.icon} />
              <IonLabel>
                <h2>{t(`demos.${item.key}.title`)}</h2>
                <p>{t(`demos.catalogItems.${item.key}`)}</p>
              </IonLabel>
            </IonItem>
          ))}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
