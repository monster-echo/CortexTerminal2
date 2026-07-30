import { invoke } from "../runtime";
import {
  PurchasePlanResponseSchema,
  type PurchasePlanResponse,
  RestorePurchasesResponseSchema,
  type RestorePurchasesResponse,
} from "../../schemas/bridgeSchema";

/**
 * In-app purchase bridge. Native side (AppBridge.Billing) drives the StoreKit purchase via
 * IapService, then POSTs the signed receipt to the gateway verify endpoint. Both calls return a
 * structured response — check `.success` and `.errorCode` rather than catching; only transport /
 * schema errors throw. Purchase calls can take longer than the default bridge timeout (StoreKit
 * prompts + network verify), so the timeout is raised.
 */
const IAP_TIMEOUT_MS = 60000;

export const billingBridge = {
  purchasePlan: (planCode: string): Promise<PurchasePlanResponse> =>
    invoke(
      "PurchasePlanAsync",
      PurchasePlanResponseSchema,
      [planCode],
      { timeoutMs: IAP_TIMEOUT_MS },
    ),

  restorePurchases: (): Promise<RestorePurchasesResponse> =>
    invoke(
      "RestorePurchasesAsync",
      RestorePurchasesResponseSchema,
      [],
      { timeoutMs: IAP_TIMEOUT_MS },
    ),
};
