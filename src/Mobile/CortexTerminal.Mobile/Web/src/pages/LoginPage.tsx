import { useState } from "react"

export function LoginPage(props: {
  login: (username: string) => Promise<void>
  navigate: (path: string) => void
}) {
  const { login, navigate } = props
  const [username, setUsername] = useState("")
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()

    const nextUsername = username.trim()
    if (!nextUsername) {
      setErrorMessage("Username is required.")
      return
    }

    setIsSubmitting(true)
    setErrorMessage(null)

    try {
      await login(nextUsername)
      navigate("/sessions")
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Login failed.")
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <section>
      <h2>Sign in</h2>
      <p>Use the development login endpoint to enter the Gateway console.</p>
      <form onSubmit={handleSubmit}>
        <label>
          Username
          <input
            autoComplete="username"
            onChange={(event) => setUsername(event.target.value)}
            value={username}
          />
        </label>
        <button disabled={isSubmitting} type="submit">
          Sign in
        </button>
      </form>
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
    </section>
  )
}
