using MessagePack;

namespace CortexTerminal.Contracts.Auth;

[MessagePackObject]
public sealed record DevLoginRequest(
    [property: Key(0)] string Username,
    [property: Key(1)] string Password
);

[MessagePackObject]
public sealed record DevLoginResponse([property: Key(0)] string AccessToken);
