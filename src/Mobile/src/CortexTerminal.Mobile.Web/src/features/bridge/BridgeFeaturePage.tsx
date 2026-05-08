import {
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
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { nativeBridge } from "../../bridge/nativeBridge";
import ActionResultCard from "../../components/ActionResultCard";

function createDemoBinary(byteLength = 24) {
  const bytes = new Uint8Array(byteLength);
  for (let index = 0; index < byteLength; index += 1) {
    bytes[index] = index % 256;
  }
  return bytes;
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary);
}

function summarizeBase64(base64: string, byteLength: number) {
  return `byteLength=${byteLength}\nbase64=${base64.slice(0, 48)}${base64.length > 48 ? "..." : ""}`;
}

export default function BridgeFeaturePage() {
  const { t } = useTranslation();
  const [resultTitle, setResultTitle] = useState(t("bridge.initialTitle"));
  const [resultDetail, setResultDetail] = useState(
    t("bridge.initialDetail"),
  );
  const [incomingTitle, setIncomingTitle] = useState(t("bridge.initialIncomingTitle"));
  const [incomingDetail, setIncomingDetail] = useState(
    t("bridge.initialIncomingDetail"),
  );

  useEffect(() => {
    const onNativeMessage = (event: Event) => {
      try {
        const customEvent = event as CustomEvent;
        const raw = customEvent.detail?.message;
        const data = typeof raw === "string" ? JSON.parse(raw) : raw;
        if (!data || !String(data.type ?? "").startsWith("bridgeDemo.")) {
          return;
        }

        if (data.type === "bridgeDemo.text") {
          setIncomingTitle(t("bridge.incomingText"));
          setIncomingDetail(JSON.stringify(data, null, 2));
          return;
        }

        if (data.type === "bridgeDemo.binary") {
          setIncomingTitle(t("bridge.incomingBinary"));
          setIncomingDetail(
            `${JSON.stringify(
              {
                ...data,
                base64: undefined,
              },
              null,
              2,
            )}\n${summarizeBase64(data.base64 ?? "", data.byteLength ?? 0)}`,
          );
          return;
        }

        if (data.type === "bridgeDemo.response") {
          setIncomingTitle(`${t("bridge.incomingResponse")}${data.direction}`);
          setIncomingDetail(JSON.stringify(data, null, 2));
        }
      } catch (error) {
        console.warn("Failed to parse bridge demo message", error);
      }
    };

    window.addEventListener("HybridWebViewMessageReceived", onNativeMessage);
    return () => {
      window.removeEventListener(
        "HybridWebViewMessageReceived",
        onNativeMessage,
      );
    };
  }, [t]);

  const runAction = async (title: string, action: () => Promise<string>) => {
    try {
      const detail = await action();
      setResultTitle(title);
      setResultDetail(detail);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(title);
      setResultDetail(`${t("bridge.errorPrefix")}${message}`);
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("bridge.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("bridge.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>
              {t("bridge.cardSubtitle")}
            </IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {t("bridge.cardContent")}
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("bridge.infoSection")}</IonLabel>
          </IonListHeader>
          <IonItem button detail routerLink="/bridge/stream">
            <IonLabel>
              <h2>{t("bridge.streamLink")}</h2>
              <p>{t("bridge.streamLinkDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.platformInfo"), async () => {
                const info = await nativeBridge.getPlatformInfo();
                return JSON.stringify(info, null, 2);
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.platformInfo")}</h2>
              <p>{t("bridge.platformInfoDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.appInfo"), async () => {
                const info = await nativeBridge.getAppInfo();
                return JSON.stringify(info, null, 2);
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.appInfo")}</h2>
              <p>{t("bridge.appInfoDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.systemInfo"), async () => {
                const info = await nativeBridge.getSystemInfo();
                return JSON.stringify(info, null, 2);
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.systemInfo")}</h2>
              <p>{t("bridge.systemInfoDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.capabilities"), async () => {
                const capabilities = await nativeBridge.getCapabilities();
                return JSON.stringify(capabilities, null, 2);
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.capabilities")}</h2>
              <p>{t("bridge.capabilitiesDesc")}</p>
            </IonLabel>
          </IonItem>

          <IonListHeader>
            <IonLabel>{t("bridge.invokeSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.hello"), async () => {
                const result = await nativeBridge.hello();
                return result.message;
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.hello")}</h2>
              <p>{t("bridge.helloDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.greet"), async () => {
                const result = await nativeBridge.greet("开发者", "zh");
                return JSON.stringify(result, null, 2);
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.greet")}</h2>
              <p>{t("bridge.greetDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.kvTest"), async () => {
                const value = `bridge-demo-${Date.now()}`;
                await nativeBridge.setStringValue(
                  "template.bridge.demo",
                  value,
                );
                const roundtrip = await nativeBridge.getStringValue(
                  "template.bridge.demo",
                );
                return `${t("bridge.kvWrite")}${value}\n${t("bridge.kvRead")}${roundtrip}`;
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.kvTest")}</h2>
              <p>{t("bridge.kvTestDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.textEcho"), async () => {
                const result = await nativeBridge.echoText(
                  `hello-from-js-${Date.now()}`,
                );
                return JSON.stringify(result, null, 2);
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.textEcho")}</h2>
              <p>{t("bridge.textEchoDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.binaryEcho"), async () => {
                const bytes = createDemoBinary(32);
                const result = await nativeBridge.echoBinary(
                  bytesToBase64(bytes),
                );
                return `${JSON.stringify(
                  {
                    ...result,
                    base64: undefined,
                  },
                  null,
                  2,
                )}\n${summarizeBase64(result.base64, result.byteLength)}`;
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.binaryEcho")}</h2>
              <p>{t("bridge.binaryEchoDesc")}</p>
            </IonLabel>
          </IonItem>

          <IonListHeader>
            <IonLabel>{t("bridge.rawSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.rawText"), async () => {
                const text = `raw-js-${Date.now()}`;
                nativeBridge.sendRaw({
                  type: "bridgeDemo.text",
                  source: "js",
                  text,
                  sentAt: new Date().toISOString(),
                });
                return `${t("bridge.rawTextResult")}${text}`;
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.rawText")}</h2>
              <p>{t("bridge.rawTextDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.rawBinary"), async () => {
                const bytes = createDemoBinary(20);
                const base64 = bytesToBase64(bytes);
                nativeBridge.sendRaw({
                  type: "bridgeDemo.binary",
                  source: "js",
                  byteLength: bytes.length,
                  base64,
                  sentAt: new Date().toISOString(),
                });
                return `${t("bridge.rawBinaryResult")}\n${summarizeBase64(base64, bytes.length)}`;
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.rawBinary")}</h2>
              <p>{t("bridge.rawBinaryDesc")}</p>
            </IonLabel>
          </IonItem>

          <IonListHeader>
            <IonLabel>{t("bridge.pushSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.pushText"), async () => {
                await nativeBridge.sendTextMessageToJs(
                  `hello-from-csharp-${Date.now()}`,
                );
                return t("bridge.pushTextResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.pushText")}</h2>
              <p>{t("bridge.pushTextDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("bridge.pushBinary"), async () => {
                await nativeBridge.sendBinaryMessageToJs(40);
                return t("bridge.pushBinaryResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("bridge.pushBinary")}</h2>
              <p>{t("bridge.pushBinaryDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <ActionResultCard title={resultTitle} detail={resultDetail} />
        <ActionResultCard
          title={incomingTitle}
          detail={incomingDetail}
          note={t("bridge.incomingNote")}
        />
      </IonContent>
    </IonPage>
  );
}
