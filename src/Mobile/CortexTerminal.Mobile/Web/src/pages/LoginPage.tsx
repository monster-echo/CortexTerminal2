import { useState } from "react"
import { Terminal } from "lucide-react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"

export function LoginPage(props: {
  login: (username: string) => Promise<void>
  navigate: (path: string) => void
}) {
  const { login, navigate } = props
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
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
      navigate("/")
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Login failed.")
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col items-center gap-3">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-primary shadow-lg shadow-primary/25">
          <Terminal className="h-7 w-7 text-primary-foreground" />
        </div>
        <div className="text-center">
          <h1 className="text-2xl font-bold tracking-tight">CortexTerminal</h1>
          <p className="text-sm text-muted-foreground">Gateway Console</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="space-y-2">
          <label htmlFor="username" className="text-sm font-medium leading-none">
            Username
          </label>
          <Input
            id="username"
            autoComplete="username"
            onChange={(event) => setUsername(event.target.value)}
            value={username}
            placeholder="Enter your username"
          />
        </div>

        <div className="space-y-2">
          <label htmlFor="password" className="text-sm font-medium leading-none">
            Password
          </label>
          <Input
            id="password"
            type="password"
            autoComplete="current-password"
            onChange={(event) => setPassword(event.target.value)}
            value={password}
            placeholder="Enter your password"
          />
        </div>

        <Button disabled={isSubmitting} type="submit" className="w-full" size="lg">
          Sign in
        </Button>
      </form>

      {errorMessage ? (
        <Alert variant="destructive">
          <AlertDescription>{errorMessage}</AlertDescription>
        </Alert>
      ) : null}

      <p className="text-center text-sm text-muted-foreground">
        Don&apos;t have an account?{" "}
        <button
          type="button"
          onClick={() => navigate("/register")}
          className="font-medium text-primary hover:underline"
        >
          Create account
        </button>
      </p>
    </div>
  )
}
