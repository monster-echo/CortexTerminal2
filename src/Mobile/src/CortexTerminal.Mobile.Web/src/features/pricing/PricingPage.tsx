import { useState } from "react";
import {
  IonButton,
  IonCol,
  IonContent,
  IonGrid,
  IonIcon,
  IonPage,
  IonRow,
  IonSpinner,
  IonText,
  useIonToast,
} from "@ionic/react";
import { checkmarkCircleOutline, ribbonOutline, refreshOutline } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { billingBridge } from "../../bridge/modules/billingBridge";
import { authBridge } from "../../bridge/modules/authBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import { useAuthStore } from "../../store/authStore";

type PlanId = "free" | "pro_monthly" | "pro_yearly" | "pro_lifetime";

interface PlanDef {
  id: PlanId;
  /** planCode passed to billingBridge.purchasePlan; null for Free (no CTA) */
  planCode: string | null;
  /** i18n key under pricing for the plan title */
  titleKey: string;
  /** i18n key for the CTA label period (only used for Pro plans) */
  periodKey: string | null;
  workers: number;
  artifacts: number;
  scrollbackMB: number;
}

const PLANS: PlanDef[] = [
  {
    id: "free",
    planCode: null,
    titleKey: "pricing.free",
    periodKey: null,
    workers: 1,
    artifacts: 100,
    scrollbackMB: 5,
  },
  {
    id: "pro_monthly",
    planCode: "pro_monthly",
    titleKey: "pricing.pro",
    periodKey: "pricing.monthly",
    workers: 5,
    artifacts: 500,
    scrollbackMB: 20,
  },
  {
    id: "pro_yearly",
    planCode: "pro_yearly",
    titleKey: "pricing.pro",
    periodKey: "pricing.yearly",
    workers: 5,
    artifacts: 500,
    scrollbackMB: 20,
  },
  {
    id: "pro_lifetime",
    planCode: "pro_lifetime",
    titleKey: "pricing.pro",
    periodKey: "pricing.lifetime",
    workers: 5,
    artifacts: 500,
    scrollbackMB: 20,
  },
];

/** Native errorCode → i18n key. Unknown codes fall back to membershipErrFailed. */
function errorCodeToToastKey(errorCode: string | undefined): string {
  switch (errorCode) {
    case "user_cancelled":
      return "pricing.membershipErrCancelled";
    case "verify_failed":
      return "pricing.membershipErrVerify";
    default:
      return "pricing.membershipErrFailed";
  }
}

export default function PricingPage() {
  const { t } = useTranslation();
  const [presentToast] = useIonToast();
  // planCode currently being purchased (drives spinner on that plan's CTA).
  const [purchasing, setPurchasing] = useState<string | null>(null);
  const [restoring, setRestoring] = useState(false);
  // Server-verified entitlement from the most recent purchase/restore. Null until first success.
  const [isActive, setIsActive] = useState(false);

  // Pull current session so a refresh re-reads the JWT (which carries the membership tier post-verify).
  const setSession = useAuthStore((s) => s.setSession);

  /** After a successful purchase or restore, re-read session/profile so the JWT reflects the new tier. */
  const refetchMembership = async (): Promise<void> => {
    const session = await authBridge.getSession();
    if (session) {
      setSession({ username: session.username }, session.token);
    }
  };

  const handlePurchase = async (planCode: string) => {
    setPurchasing(planCode);
    try {
      const result = await billingBridge.purchasePlan(planCode);
      if (result.success && result.isActive) {
        setIsActive(true);
        await refetchMembership();
        nativeBridge.trackEvent("iap_purchase", { planCode, success: true });
        void presentToast({
          message: t("pricing.membershipUpgraded"),
          duration: 2500,
          position: "bottom",
          color: "success",
        });
      } else if (result.errorCode === "user_cancelled") {
        // No-op toast: user dismissed the StoreKit sheet themselves.
        void presentToast({
          message: t("pricing.membershipErrCancelled"),
          duration: 2000,
          position: "bottom",
          color: "warning",
        });
      } else {
        nativeBridge.trackEvent("iap_purchase", {
          planCode,
          success: false,
          errorCode: result.errorCode ?? "purchase_failed",
        });
        void presentToast({
          message: t(errorCodeToToastKey(result.errorCode)),
          duration: 3000,
          position: "bottom",
          color: "danger",
        });
      }
    } catch (e) {
      // Transport/schema errors only — billingBridge does not throw on IAP failure.
      nativeBridge.trackEvent("iap_purchase", {
        planCode,
        success: false,
        errorCode: "bridge_error",
      });
      void presentToast({
        message: e instanceof Error ? e.message : String(e),
        duration: 3000,
        position: "bottom",
        color: "danger",
      });
    } finally {
      setPurchasing(null);
    }
  };

  const handleRestore = async () => {
    setRestoring(true);
    try {
      const result = await billingBridge.restorePurchases();
      if (result.success) {
        await refetchMembership();
        nativeBridge.trackEvent("iap_restore", { success: true });
        void presentToast({
          message: t("pricing.membershipRestoreDone"),
          duration: 2500,
          position: "bottom",
          color: "success",
        });
      } else {
        nativeBridge.trackEvent("iap_restore", {
          success: false,
          errorCode: result.errorCode ?? "restore_failed",
        });
        void presentToast({
          message: t(errorCodeToToastKey(result.errorCode)),
          duration: 3000,
          position: "bottom",
          color: "danger",
        });
      }
    } catch (e) {
      void presentToast({
        message: e instanceof Error ? e.message : String(e),
        duration: 3000,
        position: "bottom",
        color: "danger",
      });
    } finally {
      setRestoring(false);
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("pricing.title")} defaultHref="/settings" />
      <IonContent fullscreen>
        <IonGrid style={{ padding: "16px 0" }}>
          <IonRow className="ion-justify-content-center">
            <IonCol size="12" size-md="8" size-lg="6">
              {/* Pitch line */}
              <div style={{ textAlign: "center", padding: "16px 16px 8px" }}>
                <IonIcon
                  icon={ribbonOutline}
                  style={{ fontSize: 40, color: "var(--ion-color-primary)" }}
                />
                <IonText>
                  <h2 style={{ margin: "12px 0 6px", fontSize: 20, fontWeight: 700 }}>
                    {t("pricing.title")}
                  </h2>
                  <p
                    style={{
                      color: "var(--ion-color-medium, #92949c)",
                      fontSize: 14,
                      lineHeight: 1.5,
                      margin: 0,
                    }}
                  >
                    {t("pricing.pitch")}
                  </p>
                </IonText>
              </div>

              {/* Plan cards */}
              <div style={{ padding: "8px 12px 0", display: "flex", flexDirection: "column", gap: 12 }}>
                {PLANS.map((plan) => {
                  const isPro = plan.planCode !== null;
                  const isThisPurchasing = purchasing === plan.planCode;
                  const ctaDisabled = isThisPurchasing || restoring || isActive;
                  return (
                    <div
                      key={plan.id}
                      data-analytics-id={`pricing_plan_${plan.id}`}
                      style={{
                        border: isPro
                          ? "1px solid var(--ion-color-primary)"
                          : "1px solid var(--ion-color-step-150, #d6d8de)",
                        borderRadius: 12,
                        padding: "16px",
                        background: isPro
                          ? "rgba(var(--ion-color-primary-rgb), 0.04)"
                          : "var(--ion-card-background, #fff)",
                      }}
                    >
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                        <span style={{ fontSize: 16, fontWeight: 700 }}>
                          {t(plan.titleKey)}
                          {isPro && plan.periodKey && (
                            <span style={{ color: "var(--ion-color-medium, #92949c)", fontWeight: 400, marginLeft: 6 }}>
                              · {t(plan.periodKey)}
                            </span>
                          )}
                        </span>
                        <span style={{ fontSize: 18, fontWeight: 700 }}>—</span>
                      </div>

                      <ul style={{ margin: "10px 0 14px", paddingLeft: 18, color: "var(--ion-color-medium, #92949c)", fontSize: 13, lineHeight: 1.7 }}>
                        <li>{t("pricing.workers", { count: plan.workers })}</li>
                        <li>{t("pricing.artifacts", { count: plan.artifacts })}</li>
                        <li>{t("pricing.scrollback", { count: plan.scrollbackMB })}</li>
                        <li>{t("pricing.connect")}</li>
                      </ul>

                      {isPro ? (
                        <IonButton
                          expand="block"
                          disabled={ctaDisabled}
                          onClick={() => plan.planCode && void handlePurchase(plan.planCode)}
                          data-analytics-id={`pricing_cta_${plan.id}`}
                        >
                          {isThisPurchasing ? (
                            <IonSpinner name="crescent" />
                          ) : isActive ? (
                            <>
                              <IonIcon slot="start" icon={checkmarkCircleOutline} />
                              {t("pricing.upgraded")}
                            </>
                          ) : (
                            t("pricing.upgrade", { period: t(plan.periodKey!) })
                          )}
                        </IonButton>
                      ) : (
                        <div
                          style={{
                            textAlign: "center",
                            fontSize: 13,
                            color: "var(--ion-color-medium, #92949c)",
                            padding: "10px 0 2px",
                          }}
                        >
                          {t("pricing.currentPlan")}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>

              {/* Restore purchases (App Store requirement) */}
              <div style={{ padding: "8px 16px 32px" }}>
                <IonButton
                  expand="block"
                  fill="outline"
                  disabled={restoring || purchasing !== null}
                  onClick={() => void handleRestore()}
                  data-analytics-id="pricing_restore"
                >
                  {restoring ? (
                    <IonSpinner name="crescent" />
                  ) : (
                    <>
                      <IonIcon slot="start" icon={refreshOutline} />
                      {t("pricing.restore")}
                    </>
                  )}
                </IonButton>
              </div>
            </IonCol>
          </IonRow>
        </IonGrid>
      </IonContent>
    </IonPage>
  );
}
