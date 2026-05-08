import {
  IonBadge,
  IonButton,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonCardTitle,
  IonContent,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonPage,
} from "@ionic/react";
import { useEffect, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { nativeBridge } from "../../bridge/nativeBridge";
import ActionResultCard from "../../components/ActionResultCard";
import "./BridgeStreamFeaturePage.css";

type StreamChunk = {
  streamId: string;
  sequence: number;
  chunkCount: number;
  byteLength: number;
  checksum: string;
  base64: string;
  sentAt: string;
};

type StreamPreset = {
  labelKey: string;
  chunkByteLength: number;
  chunkCount: number;
  intervalMs: number;
};

const streamPresets: StreamPreset[] = [
  {
    labelKey: "presetLight",
    chunkByteLength: 128,
    chunkCount: 12,
    intervalMs: 180,
  },
  {
    labelKey: "presetStandard",
    chunkByteLength: 512,
    chunkCount: 18,
    intervalMs: 220,
  },
  {
    labelKey: "presetHeavy",
    chunkByteLength: 2048,
    chunkCount: 10,
    intervalMs: 320,
  },
];

function base64ToHexPreview(base64: string, maxBytes = 16) {
  try {
    const binary = atob(base64);
    return Array.from(binary.slice(0, maxBytes))
      .map((char) => char.charCodeAt(0).toString(16).padStart(2, "0"))
      .join(" ");
  } catch {
    return "<invalid-base64>";
  }
}

export default function BridgeStreamFeaturePage() {
  const { t } = useTranslation();
  const [currentStreamId, setCurrentStreamId] = useState<string | null>(null);
  const currentStreamIdRef = useRef<string | null>(null);
  const [isStreaming, setIsStreaming] = useState(false);
  const [statusTitle, setStatusTitle] = useState(t("bridgeStream.initialTitle"));
  const [statusDetail, setStatusDetail] = useState(
    t("bridgeStream.initialDetail"),
  );
  const [commandTitle, setCommandTitle] = useState(t("bridgeStream.initialCmdTitle"));
  const [commandDetail, setCommandDetail] = useState(
    t("bridgeStream.initialCmdDetail"),
  );
  const [chunks, setChunks] = useState<StreamChunk[]>([]);

  useEffect(() => {
    currentStreamIdRef.current = currentStreamId;
  }, [currentStreamId]);

  useEffect(() => {
    const onNativeMessage = (event: Event) => {
      try {
        const customEvent = event as CustomEvent;
        const raw = customEvent.detail?.message;
        const data = typeof raw === "string" ? JSON.parse(raw) : raw;

        if (!data || !String(data.type ?? "").startsWith("bridgeStream.")) {
          return;
        }

        if (data.type === "bridgeStream.started") {
          setCurrentStreamId(data.streamId ?? null);
          setIsStreaming(true);
          setChunks([]);
          setStatusTitle(t("bridgeStream.started"));
          setStatusDetail(JSON.stringify(data, null, 2));
          return;
        }

        if (data.type === "bridgeStream.chunk") {
          const nextChunk = data as StreamChunk;
          setCurrentStreamId(nextChunk.streamId);
          setIsStreaming(true);
          setChunks((current) => [nextChunk, ...current].slice(0, 24));
          setStatusTitle(
            `${t("bridgeStream.receiving")}${nextChunk.sequence + 1}/${nextChunk.chunkCount}${t("bridgeStream.receivingEnd")}`,
          );
          setStatusDetail(
            `streamId=${nextChunk.streamId}\nbyteLength=${nextChunk.byteLength}\nchecksum=${nextChunk.checksum}`,
          );
          return;
        }

        if (data.type === "bridgeStream.completed") {
          if (
            data.streamId &&
            currentStreamIdRef.current &&
            data.streamId !== currentStreamIdRef.current
          ) {
            return;
          }

          setIsStreaming(false);
          setCurrentStreamId(null);
          setStatusTitle(t("bridgeStream.completed"));
          setStatusDetail(JSON.stringify(data, null, 2));
          return;
        }

        if (data.type === "bridgeStream.stopped") {
          if (
            data.streamId &&
            currentStreamIdRef.current &&
            data.streamId !== currentStreamIdRef.current
          ) {
            return;
          }

          setIsStreaming(false);
          setCurrentStreamId(null);
          setStatusTitle(t("bridgeStream.stopped"));
          setStatusDetail(JSON.stringify(data, null, 2));
          return;
        }

        if (data.type === "bridgeStream.error") {
          setIsStreaming(false);
          setCurrentStreamId(null);
          setStatusTitle(t("bridgeStream.failed"));
          setStatusDetail(JSON.stringify(data, null, 2));
        }
      } catch (error) {
        console.warn("Failed to parse bridge stream message", error);
      }
    };

    window.addEventListener("HybridWebViewMessageReceived", onNativeMessage);

    return () => {
      nativeBridge.sendRaw({
        type: "bridgeStream.stop",
        source: "js",
        sentAt: new Date().toISOString(),
      });
      window.removeEventListener(
        "HybridWebViewMessageReceived",
        onNativeMessage,
      );
    };
  }, [t]);

  const totalBytes = useMemo(
    () => chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0),
    [chunks],
  );

  const startStream = (preset: StreamPreset) => {
    const label = t(`bridgeStream.${preset.labelKey}`);
    setCommandTitle(`${t("bridgeStream.cmdStart")}${label}`);
    setCommandDetail(JSON.stringify(preset, null, 2));
    nativeBridge.sendRaw({
      type: "bridgeStream.start",
      source: "js",
      ...preset,
      sentAt: new Date().toISOString(),
    });
  };

  const stopStream = () => {
    setCommandTitle(t("bridgeStream.cmdStop"));
    setCommandDetail(`streamId=${currentStreamId ?? "<none>"}`);
    nativeBridge.sendRaw({
      type: "bridgeStream.stop",
      source: "js",
      streamId: currentStreamId,
      sentAt: new Date().toISOString(),
    });
  };

  return (
    <IonPage>
      <PageHeader title={t("bridgeStream.title")} defaultHref="/bridge" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("bridgeStream.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>
              {t("bridgeStream.cardSubtitle")}
            </IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {t("bridgeStream.statusLabel")}
            <IonBadge color={isStreaming ? "success" : "medium"}>
              {isStreaming ? t("bridgeStream.statusStreaming") : t("bridgeStream.statusIdle")}
            </IonBadge>
            <div className="bridge-stream-page__summary">
              {t("bridgeStream.chunkSummary")}{chunks.length}{t("bridgeStream.chunkBytes")}{totalBytes}
            </div>
          </IonCardContent>
        </IonCard>

        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("bridgeStream.commandCard")}</IonCardTitle>
            <IonCardSubtitle>
              {t("bridgeStream.commandDesc")}
            </IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            <div className="bridge-stream-page__actions">
              {streamPresets.map((preset) => (
                <IonButton
                  key={preset.labelKey}
                  onClick={() => startStream(preset)}
                >
                  {t(`bridgeStream.${preset.labelKey}`)}
                </IonButton>
              ))}
              <IonButton color="warning" fill="outline" onClick={stopStream}>
                {t("bridgeStream.stop")}
              </IonButton>
              <IonButton
                color="medium"
                fill="clear"
                onClick={() => setChunks([])}
              >
                {t("bridgeStream.clear")}
              </IonButton>
            </div>
          </IonCardContent>
        </IonCard>

        <ActionResultCard title={commandTitle} detail={commandDetail} />
        <ActionResultCard title={statusTitle} detail={statusDetail} />

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("bridgeStream.chunkSection")}</IonLabel>
          </IonListHeader>
          {chunks.length === 0 ? (
            <IonItem>
              <IonLabel>
                <h2>{t("bridgeStream.noDataTitle")}</h2>
                <p>{t("bridgeStream.noDataDesc")}</p>
              </IonLabel>
            </IonItem>
          ) : (
            chunks.map((chunk) => (
              <IonItem key={`${chunk.streamId}-${chunk.sequence}`}>
                <IonLabel>
                  <h2>
                    chunk #{chunk.sequence + 1}
                    <IonBadge style={{ marginLeft: 8 }} color="primary">
                      {chunk.byteLength} bytes
                    </IonBadge>
                  </h2>
                  <p>streamId: {chunk.streamId}</p>
                  <p>checksum: {chunk.checksum}</p>
                  <p>{t("bridgeStream.hexPreview")}{base64ToHexPreview(chunk.base64)}</p>
                  <p>{t("bridgeStream.sentAt")}{chunk.sentAt}</p>
                </IonLabel>
              </IonItem>
            ))
          )}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
