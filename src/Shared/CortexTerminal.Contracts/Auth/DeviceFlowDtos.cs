using MessagePack;

namespace CortexTerminal.Contracts.Auth;

[MessagePackObject]
public sealed record DeviceFlowStartResponse(
    [property: Key(0)] string DeviceCode,
    [property: Key(1)] string UserCode,
    [property: Key(2)] string VerificationUri,
    [property: Key(3)] int ExpiresInSeconds,
    [property: Key(4)] int PollIntervalSeconds);

[MessagePackObject]
public sealed record DeviceFlowTokenResponse(
    [property: Key(0)] string AccessToken,
    [property: Key(1)] string RefreshToken,
    [property: Key(2)] int ExpiresInSeconds);

[MessagePackObject]
public sealed record DeviceFlowPollRequest(
    [property: Key(0)] string DeviceCode);

[MessagePackObject]
public sealed record DeviceFlowVerifyRequest(
    [property: Key(0)] string UserCode);
