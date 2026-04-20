namespace CortexTerminal.Mobile.Bridge;

public sealed class TerminalBridge
{
    public byte[] ForwardInput(byte[] payload) => payload.ToArray();
    public byte[] ForwardStdout(byte[] payload) => payload.ToArray();
    public byte[] ForwardStderr(byte[] payload) => payload.ToArray();
}
