/**
 * @file AppRouter.ets
 * @brief @AppRouter decorator for declaring route entries in FeatureComponent files.
 *
 * Usage:
 *   @AppRouter({ name: "auth/Login" })
 *   @Component
 *   export struct AuthLogin { ... }
 */
import { AppRouterInfo } from '../model/AppRouterInfo'

const APP_ROUTER_MAP: Record<string, AppRouterInfo> = {}

export function getAppRouterMap(): Record<string, AppRouterInfo> {
  return APP_ROUTER_MAP
}

export function AppRouter(info: AppRouterInfo): ClassDecorator {
  return (target: ESObject) => {
    APP_ROUTER_MAP[info.name] = info
  }
}
