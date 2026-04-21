import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { LoginPage } from "./LoginPage"

describe("LoginPage", () => {
  it("submits the username and redirects to sessions", async () => {
    const login = vi.fn().mockResolvedValue(undefined)
    const navigate = vi.fn()

    render(<LoginPage login={login} navigate={navigate} />)

    fireEvent.change(screen.getByLabelText("Username"), {
      target: { value: "alice" },
    })
    fireEvent.click(screen.getByRole("button", { name: "Sign in" }))

    await waitFor(() => expect(login).toHaveBeenCalledWith("alice"))
    expect(navigate).toHaveBeenCalledWith("/sessions")
  })

  it("requires a username before submitting", async () => {
    render(<LoginPage login={vi.fn()} navigate={vi.fn()} />)

    fireEvent.click(screen.getByRole("button", { name: "Sign in" }))

    expect((await screen.findByRole("alert")).textContent).toContain("Username is required.")
  })

  it("shows login errors from the backend", async () => {
    const login = vi.fn().mockRejectedValue(new Error("Access denied."))

    render(<LoginPage login={login} navigate={vi.fn()} />)

    fireEvent.change(screen.getByLabelText("Username"), {
      target: { value: "alice" },
    })
    fireEvent.click(screen.getByRole("button", { name: "Sign in" }))

    expect((await screen.findByRole("alert")).textContent).toContain("Access denied.")
  })
})
