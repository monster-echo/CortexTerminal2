import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonInput,
  IonItem,
  IonList,
  IonModal,
  IonText,
  IonTitle,
  IonToolbar,
} from "@ionic/react";
import { close } from "ionicons/icons";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { tunnelBridge } from "../../bridge/modules/tunnelBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import { selectTunnelsForSession, useTunnelStore } from "../../store/tunnelStore";

interface PortForwardingModalProps {
  isOpen: boolean;
  sessionId: string;
  onDismiss: () => void;
}

function formatExpires(expiresAtUtc: string): string {
  const date = new Date(expiresAtUtc);
  return Number.isNaN(date.getTime()) ? expiresAtUtc : date.toLocaleString();
}

export default function PortForwardingModal({
  isOpen,
  sessionId,
  onDismiss,
}: PortForwardingModalProps) {
  const { t } = useTranslation();
  const tunnels = useTunnelStore(selectTunnelsForSession(sessionId));
  const [portInput, setPortInput] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    setError(null);
    tunnelBridge
      .listTunnels(sessionId)
      .then((data) => {
        if (!cancelled) {
          useTunnelStore.getState().setTunnels(sessionId, data.tunnels);
        }
      })
      .catch((err) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : String(err));
        }
      });
    return () => {
      cancelled = true;
    };
  }, [isOpen, sessionId]);

  const handleCreate = async () => {
    const port = parseInt(portInput, 10);
    if (Number.isNaN(port) || port < 1 || port > 65535) {
      setError(t("tunnels.invalidPort"));
      return;
    }
    setError(null);
    setCreating(true);
    try {
      const tunnel = await tunnelBridge.createTunnel(sessionId, port);
      useTunnelStore.getState().upsertTunnel(sessionId, tunnel);
      setPortInput("");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setCreating(false);
    }
  };

  const handleCopy = async (url: string) => {
    try {
      await navigator.clipboard.writeText(url);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const handleOpen = (url: string) => {
    void nativeBridge.openExternalLink(url);
  };

  const handleRevoke = async (tunnelId: string) => {
    setError(null);
    try {
      await tunnelBridge.revokeTunnel(tunnelId);
      useTunnelStore.getState().removeTunnel(sessionId, tunnelId);
      const data = await tunnelBridge.listTunnels(sessionId);
      useTunnelStore.getState().setTunnels(sessionId, data.tunnels);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  return (
    <IonModal isOpen={isOpen} onDidDismiss={onDismiss}>
      <IonHeader>
        <IonToolbar>
          <IonTitle>{t("tunnels.title")}</IonTitle>
          <IonButtons slot="end">
            <IonButton onClick={onDismiss}>
              <IonIcon slot="icon-only" icon={close} />
            </IonButton>
          </IonButtons>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 16,
            padding: "16px 16px 24px",
          }}
        >
          {error && (
            <IonText color="danger">
              <p style={{ fontSize: 14, fontWeight: 500, margin: 0 }}>{error}</p>
            </IonText>
          )}

          <div>
            <IonItem lines="none" style={{ padding: 0 }}>
              <IonInput
                type="number"
                value={portInput}
                onIonInput={(e) => setPortInput(e.detail.value ?? "")}
                placeholder={t("tunnels.portPlaceholder")}
                label={t("tunnels.portLabel")}
                labelPlacement="stacked"
                disabled={creating}
              />
            </IonItem>
            <IonButton
              expand="block"
              disabled={creating}
              onClick={() => void handleCreate()}
              style={{ marginTop: 12 }}
            >
              {creating ? t("tunnels.creating") : t("tunnels.create")}
            </IonButton>
          </div>

          {tunnels.length === 0 ? (
            <IonText color="medium">
              <p style={{ fontSize: 14, margin: 0 }}>{t("tunnels.noTunnels")}</p>
            </IonText>
          ) : (
            <IonList lines="inset">
              {tunnels.map((tunnel) => (
                <IonItem key={tunnel.tunnelId}>
                  <div style={{ width: "100%", padding: "8px 0" }}>
                    <div style={{ fontWeight: 600 }}>
                      {t("tunnels.portLabel")}: {tunnel.port}
                    </div>
                    <div
                      style={{
                        fontSize: 12,
                        color: "var(--ion-color-medium)",
                        marginTop: 2,
                      }}
                    >
                      {t("tunnels.expires", { time: formatExpires(tunnel.expiresAtUtc) })}
                    </div>
                    <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                      <IonButton size="small" onClick={() => void handleCopy(tunnel.url)}>
                        {t("tunnels.copyLink")}
                      </IonButton>
                      <IonButton size="small" onClick={() => handleOpen(tunnel.url)}>
                        {t("tunnels.open")}
                      </IonButton>
                      <IonButton
                        size="small"
                        fill="outline"
                        color="danger"
                        onClick={() => void handleRevoke(tunnel.tunnelId)}
                      >
                        {t("tunnels.revoke")}
                      </IonButton>
                    </div>
                  </div>
                </IonItem>
              ))}
            </IonList>
          )}
        </div>
      </IonContent>
    </IonModal>
  );
}
