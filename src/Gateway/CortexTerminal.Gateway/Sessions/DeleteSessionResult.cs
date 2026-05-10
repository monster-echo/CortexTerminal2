namespace CortexTerminal.Gateway.Sessions;

public sealed record DeleteSessionResult(
    bool IsSuccess,
    string? ErrorCode = null)
{
    public static DeleteSessionResult Success() => new(true);

    public static DeleteSessionResult Failure(string errorCode) => new(false, errorCode);
}
