import { ReactNode } from "react";
import { IonSplitPane, IonRouterOutlet } from "@ionic/react";
import AppSidebar from "./AppSidebar";

interface AppLayoutProps {
  children: ReactNode;
}

export default function AppLayout({ children }: AppLayoutProps) {
  return (
    <IonSplitPane contentId="main-content" when={false}>
      <AppSidebar />
      <IonRouterOutlet id="main-content">
        {children}
      </IonRouterOutlet>
    </IonSplitPane>
  );
}
