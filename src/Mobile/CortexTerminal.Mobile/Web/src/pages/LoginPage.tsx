import { useState } from "react"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"

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
    <div className="flex min-h-[calc(100vh-12rem)] items-center justify-center">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>Sign in</CardTitle>
          <CardDescription>
            Use the development login endpoint to enter the Gateway console.
          </CardDescription>
        </CardHeader>
        <CardContent>
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
              />
            </div>
            <Button disabled={isSubmitting} type="submit" className="w-full">
              Sign in
            </Button>
          </form>
          {errorMessage ? (
            <Alert variant="destructive" className="mt-4">
              <AlertDescription>{errorMessage}</AlertDescription>
            </Alert>
          ) : null}
        </CardContent>
      </Card>
    </div>
  )
}
