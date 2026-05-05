import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { LoginPage } from "./LoginPage"
import type { NativeBridge } from "../bridge/types"

function createMockBridge(responses: Record<string, unknown> = {}): NativeBridge {
  return {
    async request<T>(channel: string, method: string, _payload?: unknown): Promise<T> {
      const key = `${channel}:${method}`
      const resp = responses[key]
      if (resp instanceof Error) throw resp
      if (resp !== undefined) return resp as T
      return undefined as unknown as T
    },
    onEvent: vi.fn(() => () => {}),
  }
}

/**
 * Simulates an Ionic ionInput event on an IonInput element.
 * Ionic dispatches a CustomEvent with detail.value.
 */
function fireIonInput(element: Element, value: string) {
  act(() => {
    element.dispatchEvent(
      new CustomEvent("ionInput", {
        bubbles: true,
        detail: { value },
      }),
    )
  })
}

describe("LoginPage", () => {
  it("renders phone number input and OAuth buttons", () => {
    const bridge = createMockBridge()

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    expect(screen.getByText("CortexTerminal")).toBeTruthy()
    expect(screen.getByPlaceholderText("Phone number")).toBeTruthy()
    expect(screen.getByText("Get Code")).toBeTruthy()
    expect(screen.getByText("Sign in with Apple")).toBeTruthy()
    expect(screen.getByText("Continue with GitHub")).toBeTruthy()
    expect(screen.getByText("Continue with Google")).toBeTruthy()
  })

  it("disables Get Code when phone is less than 11 digits", () => {
    const bridge = createMockBridge()

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    const getcodeBtn = screen.getByText("Get Code").closest("ion-button")!
    // Ionic sets the "disabled" property on the custom element
    expect((getcodeBtn as HTMLElement & { disabled: boolean }).disabled).toBe(true)
  })

  it("enables Get Code when phone is 11 digits", () => {
    const bridge = createMockBridge()

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    const input = screen.getByPlaceholderText("Phone number")
    fireIonInput(input, "13800138000")

    const getcodeBtn = screen.getByText("Get Code").closest("ion-button")!
    expect((getcodeBtn as HTMLElement & { disabled: boolean }).disabled).toBe(false)
  })

  it("sends phone sendCode request when Get Code is clicked", async () => {
    const requestSpy = vi.fn().mockResolvedValue(undefined)
    const bridge: NativeBridge = {
      request: requestSpy,
      onEvent: vi.fn(() => () => {}),
    }

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    const input = screen.getByPlaceholderText("Phone number")
    fireIonInput(input, "13800138000")

    const getcodeBtn = screen.getByText("Get Code").closest("ion-button")!
    await act(async () => {
      fireEvent.click(getcodeBtn)
    })

    await waitFor(() =>
      expect(requestSpy).toHaveBeenCalledWith("auth", "phone.sendCode", { phone: "13800138000" })
    )
  })

  it("shows Login button after code is sent", async () => {
    const bridge = createMockBridge({
      "auth:phone.sendCode": { ok: true },
    })

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    const input = screen.getByPlaceholderText("Phone number")
    fireIonInput(input, "13800138000")

    const getcodeBtn = screen.getByText("Get Code").closest("ion-button")!
    await act(async () => {
      fireEvent.click(getcodeBtn)
    })

    // The Login button should appear after code is sent
    expect(await screen.findByText("Login")).toBeTruthy()
  })

  it("sends verifyCode request on phone login", async () => {
    const requestSpy = vi.fn()
    requestSpy.mockResolvedValueOnce(undefined) // sendCode
    requestSpy.mockResolvedValueOnce({ username: "phone_8000" }) // verifyCode
    const bridge: NativeBridge = {
      request: requestSpy,
      onEvent: vi.fn(() => () => {}),
    }

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    // Enter phone number
    const phoneInput = screen.getByPlaceholderText("Phone number")
    fireIonInput(phoneInput, "13800138000")

    // Click Get Code
    const getcodeBtn = screen.getByText("Get Code").closest("ion-button")!
    await act(async () => {
      fireEvent.click(getcodeBtn)
    })

    // Wait for Login button to appear
    await waitFor(() => screen.getByText("Login"))

    // Enter verification code - use querySelector to get the ion-input (not the native input)
    const codeInput = document.querySelectorAll("ion-input")[1]!
    fireIonInput(codeInput, "123456")

    // Click Login
    const loginBtn = screen.getByText("Login").closest("ion-button")!
    await act(async () => {
      fireEvent.click(loginBtn)
    })

    await waitFor(() =>
      expect(requestSpy).toHaveBeenCalledWith("auth", "phone.verifyCode", { phone: "13800138000", code: "123456" })
    )
  })

  it("triggers OAuth start when clicking Apple button", async () => {
    const requestSpy = vi.fn().mockResolvedValue(undefined)
    const bridge: NativeBridge = {
      request: requestSpy,
      onEvent: vi.fn(() => () => {}),
    }

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    const appleBtn = screen.getByText("Sign in with Apple").closest("ion-button")!
    fireEvent.click(appleBtn)

    await waitFor(() =>
      expect(requestSpy).toHaveBeenCalledWith("auth", "oauth.start", { provider: "apple" })
    )
  })

  it("triggers OAuth start when clicking GitHub button", async () => {
    const requestSpy = vi.fn().mockResolvedValue(undefined)
    const bridge: NativeBridge = {
      request: requestSpy,
      onEvent: vi.fn(() => () => {}),
    }

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    const githubBtn = screen.getByText("Continue with GitHub").closest("ion-button")!
    fireEvent.click(githubBtn)

    await waitFor(() =>
      expect(requestSpy).toHaveBeenCalledWith("auth", "oauth.start", { provider: "github" })
    )
  })
})
