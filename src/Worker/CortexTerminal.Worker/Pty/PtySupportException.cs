namespace CortexTerminal.Worker.Pty;

public sealed class PtySupportException(string errorCode, string message)
    : InvalidOperationException(message)
{
    public string ErrorCode { get; } = errorCode;
}
