/**
 * @file AppRouter.ets
 * @brief Route registration for FeatureComponent files.
 *
 * Usage:
 *   registerRoute({ name: "auth/Login" })
 *   @Component
 *   export struct AuthLogin { ... }
 */
import { AppRouterInfo } from '../model/AppRouterInfo'

const APP_ROUTER_MAP: Record<string, AppRouterInfo> = {}

export function getAppRouterMap(): Record<string, AppRouterInfo> {
  return APP_ROUTER_MAP
}

export function registerRoute(info: AppRouterInfo): void {
  APP_ROUTER_MAP[info.name] = info
}
