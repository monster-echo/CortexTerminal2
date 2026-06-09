namespace CortexTerminal.Gateway.Sessions;

public sealed record RenameSessionResult(
    bool IsSuccess,
    string? ErrorCode = null)
{
    public static RenameSessionResult Success() => new(true);

    public static RenameSessionResult Failure(string errorCode) => new(false, errorCode);
}
