import { useState } from "react"
import { Terminal } from "lucide-react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"

export function RegisterPage(props: { navigate: (path: string) => void }) {
  const { navigate } = props
  const [name, setName] = useState("")
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setErrorMessage(null)

    if (!name.trim() || !username.trim() || !password.trim()) {
      setErrorMessage("All fields are required.")
      return
    }

    if (password.length < 6) {
      setErrorMessage("Password must be at least 6 characters.")
      return
    }

    setIsSubmitting(true)

    try {
      const response = await fetch("/api/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: name.trim(), username: username.trim(), password }),
      })
      if (!response.ok) {
        const text = await response.text()
        throw new Error(text || "Registration failed.")
      }
      setSuccessMessage("Account created! Redirecting to login...")
      setTimeout(() => navigate("/login"), 1500)
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Registration failed.")
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
          <h1 className="text-2xl font-bold tracking-tight">Create Account</h1>
          <p className="text-sm text-muted-foreground">Join CortexTerminal Gateway</p>
        </div>
      </div>

      {successMessage ? (
        <Alert>
          <AlertDescription>{successMessage}</AlertDescription>
        </Alert>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <label htmlFor="name" className="text-sm font-medium leading-none">
              Full Name
            </label>
            <Input
              id="name"
              autoComplete="name"
              onChange={(event) => setName(event.target.value)}
              value={name}
              placeholder="Your full name"
            />
          </div>

          <div className="space-y-2">
            <label htmlFor="username" className="text-sm font-medium leading-none">
              Username
            </label>
            <Input
              id="username"
              autoComplete="username"
              onChange={(event) => setUsername(event.target.value)}
              value={username}
              placeholder="Choose a username"
            />
          </div>

          <div className="space-y-2">
            <label htmlFor="password" className="text-sm font-medium leading-none">
              Password
            </label>
            <Input
              id="password"
              type="password"
              autoComplete="new-password"
              onChange={(event) => setPassword(event.target.value)}
              value={password}
              placeholder="At least 6 characters"
            />
          </div>

          <Button disabled={isSubmitting} type="submit" className="w-full" size="lg">
            Create account
          </Button>
        </form>
      )}

      {errorMessage ? (
        <Alert variant="destructive">
          <AlertDescription>{errorMessage}</AlertDescription>
        </Alert>
      ) : null}

      <p className="text-center text-sm text-muted-foreground">
        Already have an account?{" "}
        <button
          type="button"
          onClick={() => navigate("/login")}
          className="font-medium text-primary hover:underline"
        >
          Back to login
        </button>
      </p>
    </div>
  )
}
