import type { NativeBridge } from "../bridge/types"

export interface AuthSession {
  token: string
  username: string
}

export interface AuthService {
  getSession(): Promise<AuthSession | null>
  isAuthenticated(): Promise<boolean>
  logout(): Promise<void>
  sendCode(phone: string): Promise<void>
  verifyCode(phone: string, code: string): Promise<string>
}

export function createAuthService(bridge: NativeBridge): AuthService {
  let cached: AuthSession | null = null

  return {
    async getSession() {
      if (cached) return cached
      const result = await bridge.request<AuthSession | null>("auth", "getSession")
      cached = result
      return result
    },
    async isAuthenticated() {
      const session = await this.getSession()
      return session !== null
    },
    async logout() {
      await bridge.request("auth", "logout")
      cached = null
    },
    async sendCode(phone: string) {
      await bridge.request("auth", "phone.sendCode", { phone })
    },
    async verifyCode(phone: string, code: string) {
      const result = await bridge.request<{ username: string }>("auth", "phone.verifyCode", { phone, code })
      cached = { token: "", username: result.username }
      return result.username
    },
  }
}
