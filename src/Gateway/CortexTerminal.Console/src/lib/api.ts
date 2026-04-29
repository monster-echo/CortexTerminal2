import { createConsoleApi } from '@/services/console-api'
import type { ConsoleApi } from '@/services/console-api'
import { useAuthStore } from '@/stores/auth-store'

let _api: ConsoleApi | null = null

export function getApi(): ConsoleApi {
  if (!_api) {
    _api = createConsoleApi({
      getToken: () => useAuthStore.getState().auth.accessToken,
      onUnauthorized: () => useAuthStore.getState().auth.reset(),
      onTokenRefreshed: (newToken) =>
        useAuthStore.getState().auth.setAccessToken(newToken),
    })
  }
  return _api
}
