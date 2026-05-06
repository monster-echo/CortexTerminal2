# Phone Number + Apple Sign In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add phone number SMS verification login and Apple Sign In to CortexTerminal Mobile, alongside existing GitHub/Google OAuth.

**Architecture:** Phone login uses Gateway REST endpoints (`send-code`/`verify`) proxied through the Bridge. Apple Sign In reuses the existing OAuth browser redirect + deep link pattern. LoginPage is redesigned with phone input at top, three OAuth buttons below.

**Tech Stack:** .NET 10 Minimal APIs, Alibaba Cloud SMS SDK, Apple OAuth (code exchange via `appleid.apple.com`), Ionic React, Vitest.

---

## File Structure

### Gateway Backend — New Files
- `src/Gateway/CortexTerminal.Gateway/Auth/PhoneAuthOptions.cs` — Aliyun SMS + Apple OAuth config models
- `src/Gateway/CortexTerminal.Gateway/Auth/PhoneCodeStore.cs` — In-memory verification code storage with rate limiting

### Gateway Backend — Modified Files
- `src/Gateway/CortexTerminal.Gateway/Program.cs` — Add 4 new endpoints (phone send-code, phone verify, apple auth, apple callback)
- `src/Gateway/CortexTerminal.Gateway/appsettings.json` — Add `PhoneAuth` and `AppleOAuth` config sections
- `src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj` — Add `Aliyun.CSharpSDK.Core` NuGet package

### Mobile C# — Modified Files
- `src/Mobile/CortexTerminal.Mobile/Services/Auth/AuthService.cs` — Add `phone.sendCode` and `phone.verifyCode` handlers
- `src/Mobile/CortexTerminal.Mobile/Services/Auth/OAuthService.cs` — Add `"apple"` to provider whitelist
- `src/Mobile/CortexTerminal.Mobile/MauiProgram.cs` — Register new bridge handlers

### Mobile Web — Modified Files
- `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.tsx` — Redesign with phone input + 3 OAuth buttons
- `src/Mobile/CortexTerminal.Mobile/Web/src/services/auth.ts` — Add `sendCode` and `verifyCode` methods

### Mobile Web — Test Files
- `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.spec.tsx` — Update tests for new UI

---

## Task 1: Gateway — Phone Auth Config + Code Store

**Files:**
- Create: `src/Gateway/CortexTerminal.Gateway/Auth/PhoneAuthOptions.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Auth/PhoneCodeStore.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/appsettings.json`
- Modify: `src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj`

- [ ] **Step 1: Add Aliyun SDK NuGet package**

```bash
cd /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Gateway/CortexTerminal.Gateway
dotnet add package Aliyun.CSharpSDK.Core
```

- [ ] **Step 2: Create PhoneAuthOptions.cs**

```csharp
namespace CortexTerminal.Gateway.Auth;

public sealed class PhoneAuthOptions
{
    public string AccessKeyId { get; set; } = "";
    public string AccessKeySecret { get; set; } = "";
    public string SignName { get; set; } = "";
    public string TemplateCode { get; set; } = "";
    public string RegionId { get; set; } = "cn-hangzhou";
}

public sealed class AppleOAuthOptions
{
    public string ClientId { get; set; } = "";
    public string TeamId { get; set; } = "";
    public string KeyId { get; set; } = "";
    public string PrivateKey { get; set; } = "";
}
```

- [ ] **Step 3: Create PhoneCodeStore.cs**

```csharp
using System.Collections.Concurrent;

namespace CortexTerminal.Gateway.Auth;

public sealed class PhoneCodeStore
{
    private readonly ConcurrentDictionary<string, PhoneCodeEntry> _codes = new();

    public string Create(string phone)
    {
        RemoveExpired();

        // Rate limit: if an entry exists and hasn't expired, reject
        if (_codes.TryGetValue(phone, out var existing) && existing.ExpiresAtUtc > DateTimeOffset.UtcNow)
            throw new InvalidOperationException("RATE_LIMITED");

        var code = Random.Shared.Next(100000, 999999).ToString();
        _codes[phone] = new PhoneCodeEntry(code, phone, DateTimeOffset.UtcNow.AddMinutes(5));
        return code;
    }

    public bool Verify(string phone, string inputCode)
    {
        if (!_codes.TryRemove(phone, out var entry))
            return false;

        if (entry.ExpiresAtUtc < DateTimeOffset.UtcNow)
            return false;

        return entry.Code == inputCode;
    }

    private void RemoveExpired()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var kvp in _codes)
        {
            if (kvp.Value.ExpiresAtUtc < now)
                _codes.TryRemove(kvp.Key, out _);
        }
    }

    private sealed record PhoneCodeEntry(string Code, string Phone, DateTimeOffset ExpiresAtUtc);
}
```

- [ ] **Step 4: Update appsettings.json**

Add two new sections inside the root object (after `"Auth"`):

```json
"PhoneAuth": {
    "AccessKeyId": "",
    "AccessKeySecret": "",
    "SignName": "",
    "TemplateCode": "",
    "RegionId": "cn-hangzhou"
},
"AppleOAuth": {
    "ClientId": "",
    "TeamId": "",
    "KeyId": "",
    "PrivateKey": ""
}
```

- [ ] **Step 5: Register services in Program.cs**

At the top of `Program.cs` (around line 83, after `builder.Services.AddSingleton<OAuthStateService>();`), add:

```csharp
builder.Services.AddSingleton<PhoneCodeStore>();
var phoneAuthOptions = new PhoneAuthOptions();
builder.Configuration.GetSection("PhoneAuth").Bind(phoneAuthOptions);
var appleOAuthOptions = new AppleOAuthOptions();
builder.Configuration.GetSection("AppleOAuth").Bind(appleOAuthOptions);
```

Also add the using at the top of the file (it's already there from existing code using `CortexTerminal.Gateway.Auth`).

- [ ] **Step 6: Build and verify**

```bash
cd /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Gateway/CortexTerminal.Gateway
dotnet build
```

Expected: Build succeeded, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway/Auth/PhoneAuthOptions.cs src/Gateway/CortexTerminal.Gateway/Auth/PhoneCodeStore.cs src/Gateway/CortexTerminal.Gateway/appsettings.json src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj src/Gateway/CortexTerminal.Gateway/Program.cs
git commit -m "feat(gateway): add phone auth config models and verification code store"
```

---

## Task 2: Gateway — Phone Auth Endpoints

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs`

- [ ] **Step 1: Add the send-code endpoint**

In `Program.cs`, after the Google OAuth callback endpoint (around line 448), add:

```csharp
app.MapPost("/api/auth/phone/send-code", async (SendCodeRequest request, PhoneCodeStore codeStore, IAuditLogStore auditLog, IServiceProvider serviceProvider, IWebHostEnvironment env) =>
{
    // Validate phone format: 11 digits
    if (string.IsNullOrEmpty(request.Phone) || request.Phone.Length != 11 || !request.Phone.All(char.IsDigit))
        return Results.BadRequest(new { error = "Invalid phone number" });

    string code;
    try
    {
        code = codeStore.Create(request.Phone);
    }
    catch (InvalidOperationException)
    {
        return Results.StatusCode(429);
    }

    if (env.IsDevelopment())
    {
        // Development: log code, don't send SMS
        Console.WriteLine($"[PhoneAuth] Verification code for {request.Phone}: {code}");
    }
    else
    {
        // Production: send SMS via Aliyun
        if (string.IsNullOrEmpty(phoneAuthOptions.AccessKeyId))
            return Results.BadRequest(new { error = "Phone auth is not configured" });

        try
        {
            var client = new Aliyun.CSharpSDK.Core.DefaultAcsClient(
                Aliyun.CSharpSDK.Core.Profile.DefaultProfile.GetProfile(
                    phoneAuthOptions.RegionId, phoneAuthOptions.AccessKeyId, phoneAuthOptions.AccessKeySecret));
            var request2 = new Aliyun.CSharpSDK.Core.Common.Request();
            request2.Domain = "dysmsapi.aliyuncs.com";
            request2.Version = "2017-05-25";
            request2.Action = "SendSms";
            request2.Method = "POST";
            request2.AddQueryParameters("PhoneNumbers", request.Phone);
            request2.AddQueryParameters("SignName", phoneAuthOptions.SignName);
            request2.AddQueryParameters("TemplateCode", phoneAuthOptions.TemplateCode);
            request2.AddQueryParameters("TemplateParam", $"{{\"code\":\"{code}\"}}");
            var response = client.GetCommonResponse(request2);
            if (response.HttpResponse.Status != 200 || response.Data.Contains("\"Code\":\"OK\"") == false)
            {
                Console.WriteLine($"[PhoneAuth] SMS send failed: {response.Data}");
                return Results.StatusCode(500);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[PhoneAuth] SMS send error: {ex.Message}");
            return Results.StatusCode(500);
        }
    }

    return Results.Ok(new { ok = true });
}).AllowAnonymous();
```

- [ ] **Step 2: Add the verify endpoint**

Right after the send-code endpoint:

```csharp
app.MapPost("/api/auth/phone/verify", async (VerifyCodeRequest request, PhoneCodeStore codeStore, IAuditLogStore auditLog, IServiceProvider serviceProvider) =>
{
    if (string.IsNullOrEmpty(request.Phone) || string.IsNullOrEmpty(request.Code))
        return Results.BadRequest(new { error = "Phone and code are required" });

    if (!codeStore.Verify(request.Phone, request.Code))
        return Results.BadRequest(new { error = "Invalid or expired verification code" });

    var providerId = $"+86{request.Phone}";
    var last4 = request.Phone[^4..];
    var username = $"phone_{last4}";
    var displayName = $"{request.Phone[..3]}****{last4}";

    var dbUser = await EnsureUser(serviceProvider, username, null, displayName, null, "phone", providerId);
    if (dbUser is null || dbUser.Status == "disabled")
        return Results.BadRequest(new { error = "Account disabled" });

    var jwt = CreateAccessToken(dbUser.Username);
    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: dbUser.Id,
        UserName: dbUser.Username,
        Action: "user.phone_login",
        TargetEntity: "user",
        TargetId: dbUser.Id
    ));

    return Results.Ok(new { accessToken = jwt, username = dbUser.Username });
}).AllowAnonymous();
```

- [ ] **Step 3: Add the request DTOs**

Add these records at the bottom of `Program.cs` (near the existing helper methods), or add them at the top with the other using statements:

```csharp
record SendCodeRequest(string Phone);
record VerifyCodeRequest(string Phone, string Code);
```

These can go right before or after the `OAuthRedirect` helper method (around line 59).

- [ ] **Step 4: Build and verify**

```bash
cd /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Gateway/CortexTerminal.Gateway
dotnet build
```

Expected: Build succeeded, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway/Program.cs
git commit -m "feat(gateway): add phone number send-code and verify endpoints"
```

---

## Task 3: Gateway — Apple OAuth Endpoints

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs`

- [ ] **Step 1: Add Apple auth start endpoint**

After the phone verify endpoint, add:

```csharp
app.MapGet("/api/auth/apple", (string? redirect, OAuthStateService stateService, HttpContext ctx) =>
{
    if (string.IsNullOrEmpty(appleOAuthOptions.ClientId))
        return Results.BadRequest("Apple OAuth is not configured.");

    var state = stateService.Create(redirect ?? "/sessions");
    var callbackUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}/api/auth/callback/apple";
    var authorizeUrl = $"https://appleid.apple.com/auth/authorize?client_id={appleOAuthOptions.ClientId}&redirect_uri={Uri.EscapeDataString(callbackUrl)}&response_type=code&scope=name+email&response_mode=form_post&state={state}";
    return Results.Redirect(authorizeUrl);
}).AllowAnonymous();
```

- [ ] **Step 2: Add Apple auth callback endpoint**

Right after:

```csharp
app.MapPost("/api/auth/callback/apple", async (HttpContext ctx, OAuthStateService stateService, IHttpClientFactory httpClientFactory, IAuditLogStore auditLog, IServiceProvider serviceProvider) =>
{
    var code = ctx.Request.Form["code"].FirstOrDefault();
    var state = ctx.Request.Form["state"].FirstOrDefault();

    if (string.IsNullOrEmpty(code))
        return Results.Redirect("/sign-in?error=apple_denied");

    var redirectUrl = stateService.Consume(state ?? "") ?? "/sessions";

    var http = httpClientFactory.CreateClient();
    var callbackUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}/api/auth/callback/apple";

    // Generate Apple client secret JWT
    var clientSecret = CreateAppleClientSecret(appleOAuthOptions);

    // Exchange code for tokens
    var tokenResponse = await http.PostAsync("https://appleid.apple.com/auth/token", new FormUrlEncodedContent(
        new Dictionary<string, string>
        {
            ["client_id"] = appleOAuthOptions.ClientId,
            ["client_secret"] = clientSecret,
            ["code"] = code,
            ["redirect_uri"] = callbackUrl,
            ["grant_type"] = "authorization_code"
        }));

    if (!tokenResponse.IsSuccessStatusCode)
    {
        var errorBody = await tokenResponse.Content.ReadAsStringAsync();
        Console.WriteLine($"[AppleAuth] Token exchange failed: {errorBody}");
        return OAuthRedirect(redirectUrl, error: "apple_token_failed");
    }

    var tokenJson = await tokenResponse.Content.ReadFromJsonAsync<JsonElement>();
    var idToken = tokenJson.TryGetProperty("id_token", out var idTokenProp) ? idTokenProp.GetString() : null;
    if (string.IsNullOrEmpty(idToken))
        return OAuthRedirect(redirectUrl, error: "apple_id_token_missing");

    // Decode Apple ID token (JWT) to extract sub and email
    var appleSub = "";
    var appleEmail = "";
    try
    {
        var segments = idToken.Split('.');
        var payload = segments[1];
        payload = payload.Replace('-', '+').Replace('_', '/');
        switch (payload.Length % 4)
        {
            case 2: payload += "=="; break;
            case 3: payload += "="; break;
        }
        var json = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(payload));
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        appleSub = doc.RootElement.TryGetProperty("sub", out var subProp) ? subProp.GetString() ?? "" : "";
        appleEmail = doc.RootElement.TryGetProperty("email", out var emailProp) ? emailProp.GetString() ?? "" : "";
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[AppleAuth] ID token decode error: {ex.Message}");
        return OAuthRedirect(redirectUrl, error: "apple_id_token_invalid");
    }

    if (string.IsNullOrEmpty(appleSub))
        return OAuthRedirect(redirectUrl, error: "apple_user_failed");

    var username = !string.IsNullOrEmpty(appleEmail) ? appleEmail.Split('@')[0] : $"apple_{appleSub[..Math.Min(8, appleSub.Length)]}";
    var displayName = !string.IsNullOrEmpty(appleEmail) ? appleEmail : username;

    var dbUser = await EnsureUser(serviceProvider, username, appleEmail, displayName, null, "apple", appleSub);
    if (dbUser is null || dbUser.Status == "disabled")
        return OAuthRedirect(redirectUrl, error: "account_disabled");

    var jwt = CreateAccessToken(dbUser.Username);
    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: dbUser.Id,
        UserName: dbUser.Username,
        Action: "user.oauth_login",
        TargetEntity: "user",
        TargetId: dbUser.Id
    ));

    return OAuthRedirect(redirectUrl, token: jwt);
}).AllowAnonymous();
```

- [ ] **Step 3: Add Apple client secret JWT helper**

Add this static method near the `CreateAccessToken` method (around line 45):

```csharp
static string CreateAppleClientSecret(AppleOAuthOptions options)
{
    var now = DateTimeOffset.UtcNow;
    var claims = new[]
    {
        new System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Iss, options.TeamId,
        new System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Iat, now.ToUnixTimeSeconds().ToString(),
        new System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Exp, now.AddHours(1).ToUnixTimeSeconds().ToString(),
        new System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Aud, "https://appleid.apple.com",
        new System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub, options.ClientId,
    };

    // Build JWT manually using the existing signing infrastructure
    var tokenDescriptor = new Microsoft.IdentityModel.Tokens.SecurityTokenDescriptor
    {
        Issuer = options.TeamId,
        Subject = new System.Security.Claims.ClaimsIdentity(new[]
        {
            new System.Security.Claims.Claim("sub", options.ClientId),
        }),
        Expires = DateTime.UtcNow.AddHours(1),
        Audience = "https://appleid.apple.com",
        SigningCredentials = new Microsoft.IdentityModel.Tokens.SigningCredentials(
            new Microsoft.IdentityModel.Tokens.ECDsaSecurityKey(
                System.Security.Cryptography.ECDsa.CreateFromPem(options.PrivateKey)),
            Microsoft.IdentityModel.Tokens.SecurityAlgorithms.EcdsaSha256)
    };
    var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
    var token = handler.CreateToken(tokenDescriptor);
    token.Header["kid"] = options.KeyId;
    return handler.WriteToken(token);
}
```

Note: This requires `Microsoft.IdentityModel.Tokens` which is already transitively referenced via `Microsoft.AspNetCore.Authentication.JwtBearer`.

- [ ] **Step 4: Build and verify**

```bash
cd /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Gateway/CortexTerminal.Gateway
dotnet build
```

Expected: Build succeeded, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway/Program.cs
git commit -m "feat(gateway): add Apple Sign In OAuth endpoints"
```

---

## Task 4: Mobile C# — Phone Auth Bridge Handlers

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Services/Auth/AuthService.cs`
- Modify: `src/Mobile/CortexTerminal.Mobile/Services/Auth/OAuthService.cs`
- Modify: `src/Mobile/CortexTerminal.Mobile/MauiProgram.cs`

- [ ] **Step 1: Add phone auth handlers to AuthService.cs**

In `AuthService.cs`, update the `HandleAsync` switch to add the two new methods. Replace the entire `HandleAsync` method:

```csharp
public async Task<BridgeResponse> HandleAsync(BridgeMessage message, CancellationToken ct)
{
    return message.Method switch
    {
        "dev.login" => await HandleDevLoginAsync(message, ct),
        "getSession" => HandleGetSession(),
        "logout" => await HandleLogoutAsync(ct),
        "phone.sendCode" => await HandlePhoneSendCodeAsync(message, ct),
        "phone.verifyCode" => await HandlePhoneVerifyCodeAsync(message, ct),
        _ => new BridgeResponse { Ok = false, Error = $"Unknown auth method: {message.Method}" },
    };
}
```

Add these two new private methods at the bottom of the class (before the closing `}`):

```csharp
private async Task<BridgeResponse> HandlePhoneSendCodeAsync(BridgeMessage message, CancellationToken ct)
{
    try
    {
        var phone = message.Payload?.GetProperty("phone").GetString() ?? "";
        await _restApi.SendAsync("POST", "/api/auth/phone/send-code",
            JsonSerializer.Deserialize<JsonElement>(JsonSerializer.Serialize(new { phone })),
            ct);
        return new BridgeResponse { Ok = true };
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[Auth] Phone send code error: {ex.Message}");
        return new BridgeResponse { Ok = false, Error = ex.Message };
    }
}

private async Task<BridgeResponse> HandlePhoneVerifyCodeAsync(BridgeMessage message, CancellationToken ct)
{
    try
    {
        var phone = message.Payload?.GetProperty("phone").GetString() ?? "";
        var code = message.Payload?.GetProperty("code").GetString() ?? "";
        var result = await _restApi.SendAsync("POST", "/api/auth/phone/verify",
            JsonSerializer.Deserialize<JsonElement>(JsonSerializer.Serialize(new { phone, code })),
            ct);

        var accessToken = result.GetProperty("accessToken").GetString();
        var username = result.GetProperty("username").GetString();
        SetOAuthToken(accessToken!, username!);

        return new BridgeResponse
        {
            Ok = true,
            Payload = JsonSerializer.Deserialize<JsonElement>(
                JsonSerializer.Serialize(new { username })),
        };
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[Auth] Phone verify error: {ex.Message}");
        return new BridgeResponse { Ok = false, Error = ex.Message };
    }
}
```

- [ ] **Step 2: Add "apple" to OAuth provider whitelist in OAuthService.cs**

In `OAuthService.cs`, line 35, change the provider validation:

```csharp
if (provider is not ("github" or "google" or "apple"))
```

- [ ] **Step 3: Register new bridge handlers in MauiProgram.cs**

In `MauiProgram.cs`, after the existing auth handler registrations (around line 73), add:

```csharp
bridge.RegisterHandler("auth", "phone.sendCode", (msg) => authService.HandleAsync(msg, default));
bridge.RegisterHandler("auth", "phone.verifyCode", (msg) => authService.HandleAsync(msg, default));
```

- [ ] **Step 4: Build and verify**

```bash
cd /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Mobile/CortexTerminal.Mobile
dotnet build -f net10.0-ios -c Debug -p:RuntimeIdentifier=iossimulator-arm64
```

Expected: Build succeeded, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Services/Auth/AuthService.cs src/Mobile/CortexTerminal.Mobile/Services/Auth/OAuthService.cs src/Mobile/CortexTerminal.Mobile/MauiProgram.cs
git commit -m "feat(mobile): add phone auth bridge handlers and Apple OAuth provider"
```

---

## Task 5: Mobile Web — Update auth.ts Service

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/services/auth.ts`

- [ ] **Step 1: Add phone auth methods to AuthService**

Replace the entire `auth.ts` file:

```typescript
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
```

- [ ] **Step 2: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/src/services/auth.ts
git commit -m "feat(web): add sendCode and verifyCode to auth service"
```

---

## Task 6: Mobile Web — Redesign LoginPage

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.tsx`

- [ ] **Step 1: Rewrite LoginPage.tsx**

Replace the entire file:

```tsx
import { useState, useEffect, useRef } from "react"
import {
  IonPage,
  IonContent,
  IonButton,
  IonText,
  IonIcon,
  IonSpinner,
  IonInput,
} from "@ionic/react"
import { terminalOutline, logoGithub, logoGoogle, phonePortraitOutline } from "ionicons/icons"
import type { NativeBridge } from "../bridge/types"

export function LoginPage({
  bridge,
}: {
  bridge: NativeBridge
  onLogin: () => void
}) {
  const [phone, setPhone] = useState("")
  const [code, setCode] = useState("")
  const [codeSent, setCodeSent] = useState(false)
  const [countdown, setCountdown] = useState(0)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [loadingProvider, setLoadingProvider] = useState<string | null>(null)
  const timerRef = useRef<ReturnType<typeof setInterval>>()

  useEffect(() => {
    return () => {
      if (timerRef.current) clearInterval(timerRef.current)
    }
  }, [])

  useEffect(() => {
    if (countdown <= 0 && timerRef.current) {
      clearInterval(timerRef.current)
      timerRef.current = undefined
    }
  }, [countdown])

  const handleSendCode = async () => {
    if (phone.length !== 11) {
      setErrorMessage("Please enter an 11-digit phone number")
      return
    }
    setErrorMessage(null)
    setLoadingProvider("phone")
    try {
      await bridge.request("auth", "phone.sendCode", { phone })
      setCodeSent(true)
      setCountdown(60)
      timerRef.current = setInterval(() => {
        setCountdown((c) => c - 1)
      }, 1000)
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : "Failed to send code",
      )
    } finally {
      setLoadingProvider(null)
    }
  }

  const handlePhoneLogin = async () => {
    if (code.length < 4) {
      setErrorMessage("Please enter the verification code")
      return
    }
    setErrorMessage(null)
    setLoadingProvider("phone-login")
    try {
      await bridge.request("auth", "phone.verifyCode", { phone, code })
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : "Verification failed",
      )
      setLoadingProvider(null)
    }
  }

  const handleOAuth = async (provider: "github" | "google" | "apple") => {
    setErrorMessage(null)
    setLoadingProvider(provider)
    try {
      await bridge.request("auth", "oauth.start", { provider })
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : "Could not open browser.",
      )
      setLoadingProvider(null)
    }
  }

  return (
    <IonPage>
      <IonContent className="ion-padding">
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            minHeight: "100%",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: 56,
              height: 56,
              borderRadius: 16,
              backgroundColor: "var(--ion-color-primary)",
              marginBottom: 16,
            }}
          >
            <IonIcon
              icon={terminalOutline}
              style={{ fontSize: 28, color: "#fff" }}
            />
          </div>
          <h1 style={{ fontSize: 24, fontWeight: 700, margin: 0 }}>
            CortexTerminal
          </h1>
          <p
            style={{
              color: "var(--ion-color-medium)",
              fontSize: 14,
              marginBottom: 32,
            }}
          >
            Sign in to continue
          </p>

          {/* Phone number login */}
          <div style={{ width: "100%", maxWidth: 400, marginBottom: 24 }}>
            <IonInput
              type="tel"
              maxlength={11}
              placeholder="Phone number"
              value={phone}
              onIonInput={(e) => setPhone((e.detail.value ?? "").replace(/\D/g, ""))}
              disabled={loadingProvider !== null}
              style={{
                "--padding-start": "12px",
                border: "1px solid var(--ion-color-medium)",
                borderRadius: 8,
                marginBottom: 8,
                height: 44,
              }}
            >
              <div
                slot="start"
                style={{
                  paddingRight: 8,
                  borderRight: "1px solid var(--ion-color-medium)",
                  marginRight: 8,
                  color: "var(--ion-color-medium)",
                  fontSize: 14,
                }}
              >
                +86
              </div>
            </IonInput>

            <div style={{ display: "flex", gap: 8 }}>
              <IonInput
                type="number"
                maxlength={6}
                placeholder="Verification code"
                value={code}
                onIonInput={(e) => setCode((e.detail.value ?? "").replace(/\D/g, ""))}
                disabled={loadingProvider !== null || !codeSent}
                style={{
                  "--padding-start": "12px",
                  border: "1px solid var(--ion-color-medium)",
                  borderRadius: 8,
                  flex: 1,
                  height: 44,
                }}
              />
              <IonButton
                fill="outline"
                onClick={handleSendCode}
                disabled={loadingProvider !== null || countdown > 0 || phone.length !== 11}
                style={{ height: 44, margin: 0 }}
              >
                {loadingProvider === "phone" ? (
                  <IonSpinner name="crescent" />
                ) : countdown > 0 ? (
                  `${countdown}s`
                ) : codeSent ? (
                  "Resend"
                ) : (
                  "Get Code"
                )}
              </IonButton>
            </div>

            {codeSent && (
              <IonButton
                expand="block"
                onClick={handlePhoneLogin}
                disabled={loadingProvider !== null || code.length < 4}
                style={{ marginTop: 12, height: 44 }}
              >
                {loadingProvider === "phone-login" ? (
                  <IonSpinner name="crescent" />
                ) : (
                  <>
                    <IonIcon slot="start" icon={phonePortraitOutline} style={{ fontSize: 20 }} />
                    Login
                  </>
                )}
              </IonButton>
            )}
          </div>

          {/* Divider */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              width: "100%",
              maxWidth: 400,
              marginBottom: 16,
            }}
          >
            <div
              style={{
                flex: 1,
                height: 1,
                backgroundColor: "var(--ion-color-medium)",
              }}
            />
            <span
              style={{
                padding: "0 16px",
                color: "var(--ion-color-medium)",
                fontSize: 13,
              }}
            >
              or sign in with
            </span>
            <div
              style={{
                flex: 1,
                height: 1,
                backgroundColor: "var(--ion-color-medium)",
              }}
            />
          </div>

          {/* OAuth buttons */}
          <div style={{ width: "100%", maxWidth: 400 }}>
            <IonButton
              expand="block"
              fill="outline"
              onClick={() => handleOAuth("apple")}
              disabled={loadingProvider !== null}
              style={{ marginBottom: 12 }}
            >
              {loadingProvider === "apple" ? (
                <IonSpinner name="crescent" />
              ) : (
                <span style={{ fontWeight: 600 }}> Sign in with Apple</span>
              )}
            </IonButton>
            <IonButton
              expand="block"
              fill="outline"
              onClick={() => handleOAuth("github")}
              disabled={loadingProvider !== null}
              style={{ marginBottom: 12 }}
            >
              {loadingProvider === "github" ? (
                <IonSpinner name="crescent" />
              ) : (
                <>
                  <IonIcon slot="start" icon={logoGithub} style={{ fontSize: 20 }} />
                  Continue with GitHub
                </>
              )}
            </IonButton>
            <IonButton
              expand="block"
              fill="outline"
              onClick={() => handleOAuth("google")}
              disabled={loadingProvider !== null}
            >
              {loadingProvider === "google" ? (
                <IonSpinner name="crescent" />
              ) : (
                <>
                  <IonIcon slot="start" icon={logoGoogle} style={{ fontSize: 20 }} />
                  Continue with Google
                </>
              )}
            </IonButton>
          </div>

          {errorMessage && (
            <IonText color="danger">
              <p style={{ fontSize: 13, marginTop: 16 }}>{errorMessage}</p>
            </IonText>
          )}
        </div>
      </IonContent>
    </IonPage>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.tsx
git commit -m "feat(web): redesign LoginPage with phone number login and Apple Sign In"
```

---

## Task 7: Mobile Web — Update LoginPage Tests

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.spec.tsx`

- [ ] **Step 1: Rewrite LoginPage.spec.tsx**

Replace the entire file:

```tsx
import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { LoginPage } from "./LoginPage"
import type { NativeBridge } from "../bridge/types"

function createMockBridge(responses: Record<string, unknown> = {}): NativeBridge {
  return {
    async request<T>(channel: string, method: string, payload?: unknown): Promise<T> {
      const key = `${channel}:${method}`
      const resp = responses[key]
      if (resp instanceof Error) throw resp
      if (resp !== undefined) return resp as T
      return undefined as unknown as T
    },
    onEvent: vi.fn(() => () => {}),
  }
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
    expect(getcodeBtn.getAttribute("disabled")).not.toBeNull()
  })

  it("sends phone sendCode request when Get Code is clicked", async () => {
    const requestSpy = vi.fn().mockResolvedValue(undefined)
    const bridge: NativeBridge = {
      request: requestSpy,
      onEvent: vi.fn(() => () => {}),
    }

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    const input = screen.getByPlaceholderText("Phone number")
    fireEvent.ionInput(input, { value: "13800138000" })

    const getcodeBtn = screen.getByText("Get Code").closest("ion-button")!
    fireEvent.click(getcodeBtn)

    await waitFor(() =>
      expect(requestSpy).toHaveBeenCalledWith("auth", "phone.sendCode", { phone: "13800138000" })
    )
  })

  it("shows verification code input after code is sent", async () => {
    const bridge = createMockBridge({
      "auth:phone.sendCode": { ok: true },
    })

    render(<LoginPage bridge={bridge} onLogin={vi.fn()} />)

    const input = screen.getByPlaceholderText("Phone number")
    fireEvent.ionInput(input, { value: "13800138000" })

    const getcodeBtn = screen.getByText("Get Code").closest("ion-button")!
    fireEvent.click(getcodeBtn)

    expect(await screen.findByPlaceholderText("Verification code")).toBeTruthy()
    expect(screen.getByText("Login")).toBeTruthy()
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

    const phoneInput = screen.getByPlaceholderText("Phone number")
    fireEvent.ionInput(phoneInput, { value: "13800138000" })

    const getcodeBtn = screen.getByText("Get Code").closest("ion-button")!
    fireEvent.click(getcodeBtn)

    await waitFor(() => screen.getByPlaceholderText("Verification code"))

    const codeInput = screen.getByPlaceholderText("Verification code")
    fireEvent.ionInput(codeInput, { value: "123456" })

    const loginBtn = screen.getByText("Login").closest("ion-button")!
    fireEvent.click(loginBtn)

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
```

- [ ] **Step 2: Run tests**

```bash
cd /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Mobile/CortexTerminal.Mobile/Web
npx vitest run src/pages/LoginPage.spec.tsx
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.spec.tsx
git commit -m "test(web): update LoginPage tests for phone auth and Apple Sign In"
```

---

## Task 8: Build, Deploy, and Test

**Files:** No new files.

- [ ] **Step 1: Build web bundle**

```bash
cd /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Mobile/CortexTerminal.Mobile/Web
npm run build
```

Expected: `✓ built in X.XXs`

- [ ] **Step 2: Build MAUI app**

```bash
cd /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Mobile/CortexTerminal.Mobile
dotnet build -f net10.0-ios -c Debug -p:RuntimeIdentifier=iossimulator-arm64
```

Expected: Build succeeded, 0 errors.

- [ ] **Step 3: Deploy to simulator**

```bash
xcrun simctl terminate D3F906A8-6B65-4EB8-A80B-58351BBA3A18 com.cortexterminal.mobile 2>&1
xcrun simctl install D3F906A8-6B65-4EB8-A80B-58351BBA3A18 /Volumes/MacMiniDisk/workspace/CortexTerminal2/src/Mobile/CortexTerminal.Mobile/bin/Debug/net10.0-ios/iossimulator-arm64/CortexTerminal.Mobile.app
xcrun simctl launch D3F906A8-6B65-4EB8-A80B-58351BBA3A18 com.cortexterminal.mobile
```

- [ ] **Step 4: Verify login page shows phone input and all 3 OAuth buttons**

- [ ] **Step 5: Commit final build state**

```bash
git add -A
git commit -m "feat: complete phone + Apple Sign In auth implementation"
```

---

## Self-Review

**Spec coverage check:**
- [x] Phone send-code endpoint — Task 2
- [x] Phone verify endpoint — Task 2
- [x] Apple OAuth start endpoint — Task 3
- [x] Apple OAuth callback endpoint — Task 3
- [x] Aliyun SMS integration — Task 2 (with dev mode logging)
- [x] Phone auth bridge handlers in mobile — Task 4
- [x] Apple added to OAuth provider whitelist — Task 4
- [x] LoginPage redesign with phone-first layout — Task 6
- [x] auth.ts service update — Task 5
- [x] Tests updated — Task 7
- [x] Build and deploy — Task 8

**Placeholder scan:** No TBDs, TODOs, or vague steps found.

**Type consistency check:**
- `SendCodeRequest(string Phone)` / `VerifyCodeRequest(string Phone, string Code)` — used consistently in Task 2 endpoints
- `phone.sendCode` / `phone.verifyCode` — used consistently across Task 4 (C#) and Task 5-6 (TS)
- `PhoneAuthOptions` / `AppleOAuthOptions` — defined in Task 1, referenced in Tasks 2-3
- `PhoneCodeStore` — defined in Task 1, used in Task 2
