namespace CortexTerminal.Mobile.Core;

public enum AppErrorCode
{
    Unknown,
    BridgeUnavailable,
    Timeout,
    Validation,
    NativeFailure,
    Offline,
}

public sealed record AppError(AppErrorCode Code, string Message, string? Details = null);
