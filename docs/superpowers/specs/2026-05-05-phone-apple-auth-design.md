# Phone Number + Apple Sign In for CortexTerminal Mobile

## Overview

Add phone number SMS verification login and Apple Sign In to CortexTerminal Mobile, making them equal-priority options alongside existing GitHub and Google OAuth. The login page will prioritize phone number input at the top, with three OAuth buttons (Apple, GitHub, Google) below.

## Requirements

- Phone number login: +86 only, SMS via Alibaba Cloud SMS
- Apple Sign In: Gateway OAuth flow (same pattern as GitHub/Google)
- Development mode: SMS verification code logged to console (no real SMS sent)
- All API calls from the app go through the Bridge proxy pattern (no direct HTTP from WebView)

## Architecture

### Login Page Layout

```
+---------------------------------------------+
|             [App Icon]                       |
|          CortexTerminal                      |
|         Sign in to continue                  |
|                                              |
|  Phone Number                                |
|  +86 [13800138000]  [Get Code]               |
|  Verification Code                           |
|  [______]  [Login]                           |
|                                              |
|  ---------- or sign in with ----------       |
|                                              |
|  [  Sign in with Apple  ]                    |
|  [ Continue with GitHub ]                    |
|  [ Continue with Google ]                    |
+---------------------------------------------+
```

### Backend: New Gateway Endpoints

#### Phone Number Login

**`POST /api/auth/phone/send-code`** (AllowAnonymous)
- Request body: `{ "phone": "13800138000" }`
- Validates phone format (11 digits, +86)
- Rate limit: 1 request per 60 seconds per phone number
- Generates 6-digit random code
- Stores `{ code, phone, expiresAt }` in IMemoryCache with 5-minute expiration
- Production: calls Alibaba Cloud SMS API to send code
- Development: logs code to console, still stores in cache
- Response: `{ ok: true }`

**`POST /api/auth/phone/verify`** (AllowAnonymous)
- Request body: `{ "phone": "13800138000", "code": "123456" }`
- Looks up code from cache
- Validates: code matches, not expired, not used
- Removes code from cache (one-time use)
- Calls `EnsureUser(authProvider: "phone", authProviderId: phone)` to find or create user
- Generates JWT (same as existing OAuth flow)
- Response: `{ "accessToken": "...", "username": "138****8000" }`

#### Apple Sign In

**`GET /api/auth/apple?redirect=...`** (AllowAnonymous)
- Same pattern as `/api/auth/github` and `/api/auth/google`
- Redirects to Apple OAuth authorization URL
- Requires Apple Developer configuration: Services ID, Team ID, Key ID, private key

**`GET /api/auth/callback/apple`** (AllowAnonymous)
- Apple redirects here with `code` parameter
- Exchanges code for Apple ID token via `https://appleid.apple.com/auth/token`
- Decodes Apple ID token (JWT) to extract `sub` (Apple user ID) and `email`
- Calls `EnsureUser(authProvider: "apple", authProviderId: appleSub)`
- Generates CortexTerminal JWT
- Redirects to the `redirect` URL with `?token={jwt}` (same `OAuthRedirect` helper)

### Mobile App: Bridge Flow

#### Phone Number Login (in-app, no browser redirect)

```
1. User enters phone number
2. JS: bridge.request("auth", "phone.sendCode", { phone })
3. C# AuthService -> Gateway POST /api/auth/phone/send-code (via RestApiService)
4. Response back through bridge
5. User enters verification code
6. JS: bridge.request("auth", "phone.verifyCode", { phone, code })
7. C# AuthService -> Gateway POST /api/auth/phone/verify (via RestApiService)
8. C# receives { accessToken, username } -> SetOAuthToken(token, username)
9. Bridge response { ok: true, payload: { username } }
10. JS sets isAuthenticated = true
```

#### Apple Sign In (same as GitHub/Google OAuth)

```
1. User taps "Sign in with Apple"
2. JS: bridge.request("auth", "oauth.start", { provider: "apple" })
3. C# OAuthService validates "apple" is in allowed providers
4. Opens browser to Gateway /api/auth/apple?redirect=cortexterminal://auth/callback
5. Apple auth -> Gateway callback -> deep link redirect with token
6. AppDelegate.OpenUrl -> OAuthService.HandleDeepLinkAsync
7. Bridge event: oauth.success { username }
8. JS sets isAuthenticated = true
```

### User Model

No schema changes needed. Existing `User` model supports all providers:

| AuthProvider | AuthProviderId | Example |
|-------------|---------------|---------|
| `github` | GitHub user ID | `"12345"` |
| `google` | Google user ID | `"123456789"` |
| `apple` | Apple `sub` claim | `"001234.abcd"` |
| `phone` | Phone number with country code | `"+8613800138000"` |

Username for phone users: `phone_{last4digits}` (e.g., `phone_8000`).

## Files to Modify

### Gateway Backend (`src/Gateway/CortexTerminal.Gateway/`)

| File | Change |
|------|--------|
| `Program.cs` | Add 4 new endpoints: send-code, verify, apple auth, apple callback |
| New: `Services/AliyunSmsService.cs` | Alibaba Cloud SMS integration |
| New: `Models/PhoneAuthModels.cs` | SendCodeRequest, VerifyCodeRequest DTOs |
| `appsettings.json` | Add `AliyunSms` config section (AccessKeyId, AccessKeySecret, SignName, TemplateCode) and `AppleOAuth` config (ClientId, TeamId, KeyId, PrivateKey) |

### Mobile C# (`src/Mobile/CortexTerminal.Mobile/`)

| File | Change |
|------|--------|
| `Services/Auth/AuthService.cs` | Add handlers for `phone.sendCode` and `phone.verifyCode` bridge methods |
| `Services/Auth/OAuthService.cs` | Add `"apple"` to supported provider list |
| `MauiProgram.cs` | Register new bridge handlers for phone auth |

### Mobile Web (`src/Mobile/CortexTerminal.Mobile/Web/src/`)

| File | Change |
|------|--------|
| `pages/LoginPage.tsx` | Redesign: phone input + verification code UI at top, 3 OAuth buttons below |
| `services/auth.ts` | Add `sendCode(phone)` and `verifyCode(phone, code)` methods |

### No changes needed

- `Bridge/WebBridge.cs` — already generic
- `bridge/nativeBridge.ts` — already generic
- `bridge/types.ts` — already generic
- `App.tsx` — phone login returns via bridge response (not event), Apple uses existing oauth.success event
- `AppDelegate.cs` — already handles `cortexterminal://` deep links
- `Info.plist` — already has `CFBundleURLTypes` with `cortexterminal` scheme
- `Data/User.cs` — `AuthProvider`/`AuthProviderId` fields already support any provider string

## SMS Configuration (Alibaba Cloud)

Required settings in `appsettings.json`:

```json
{
  "AliyunSms": {
    "AccessKeyId": "",
    "AccessKeySecret": "",
    "SignName": "CortexTerminal",
    "TemplateCode": "SMS_123456789",
    "RegionId": "cn-hangzhou"
  }
}
```

The SMS template should contain a single variable `${code}` for the verification code.

## Apple OAuth Configuration

Required Apple Developer account setup:
1. Register a Services ID in Apple Developer Portal
2. Configure redirect URL: `https://gateway.ct.rwecho.top/api/auth/callback/apple`
3. Create a key for Sign in with Apple
4. Download the private key (.p8 file)

Required settings in `appsettings.json`:

```json
{
  "AppleOAuth": {
    "ClientId": "com.cortexterminal.mobile.service",
    "TeamId": "XXXXXXXXXX",
    "KeyId": "XXXXXXXXXX",
    "PrivateKey": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
  }
}
```

## Error Handling

- Invalid phone format: `{ ok: false, error: "Invalid phone number" }`
- Rate limit exceeded: `{ ok: false, error: "Please wait before requesting another code" }`
- Invalid/expired code: `{ ok: false, error: "Invalid or expired verification code" }`
- SMS send failure: `{ ok: false, error: "Failed to send SMS" }` (log full error server-side)
- Apple OAuth failure: handled by existing `OAuthRedirect` error path
