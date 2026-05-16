import { useState } from "react";
import { useIonToast } from "@ionic/react";
import { useTranslation } from "react-i18next";
import { useHistory } from "react-router-dom";
import { useSessionStore } from "../../store/sessionStore";
import { terminalBridge } from "../../bridge/modules/terminalBridge";

export function useCreateSession() {
  const { t } = useTranslation();
  const history = useHistory();
  const workers = useSessionStore((s) => s.workers);
  const touchSession = useSessionStore((s) => s.touchSession);
  const [presentToast] = useIonToast();

  const [showModal, setShowModal] = useState(false);
  const [selectedWorkerId, setSelectedWorkerId] = useState<string | null>(null);
  const [isCreating, setIsCreating] = useState(false);

  const onlineWorkers = workers.filter((w) => w.status !== "offline");
  const hasOnlineWorkers = onlineWorkers.length > 0;

  const openModal = () => {
    if (!hasOnlineWorkers) return;
    setSelectedWorkerId(onlineWorkers[0]?.id ?? null);
    setShowModal(true);
  };

  const closeModal = () => {
    setShowModal(false);
    setSelectedWorkerId(null);
  };

  const createSession = async () => {
    if (workers.length === 0) {
      presentToast({
        message: t("sessions.noWorkers"),
        duration: 3000,
        position: "bottom",
        color: "warning",
      });
      return;
    }

    const fontSize = 14;
    const charWidth = fontSize * 0.602;
    const charHeight = fontSize * 1.2;
    const vpWidth = window.visualViewport?.width ?? window.innerWidth;
    const vpHeight = window.visualViewport?.height ?? window.innerHeight;
    const cols = Math.floor(vpWidth / charWidth);
    const rows = Math.floor((vpHeight - 44) / charHeight);

    setIsCreating(true);
    try {
      const session = await terminalBridge.createSession(
        cols,
        rows,
        selectedWorkerId ?? undefined,
      );
      touchSession(session);
      closeModal();
      history.replace(`/sessions/${session.id}`);
      return session;
    } catch (error) {
      presentToast({
        message: error instanceof Error ? error.message : String(error),
        duration: 3000,
        position: "bottom",
        color: "danger",
      });
    } finally {
      setIsCreating(false);
    }
  };

  return {
    showModal,
    openModal,
    closeModal,
    onlineWorkers,
    hasOnlineWorkers,
    selectedWorkerId,
    setSelectedWorkerId,
    isCreating,
    createSession,
  };
}
