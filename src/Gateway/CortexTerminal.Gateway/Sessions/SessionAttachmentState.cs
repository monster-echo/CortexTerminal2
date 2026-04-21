namespace CortexTerminal.Gateway.Sessions;

public enum SessionAttachmentState
{
    Attached = 0,
    DetachedGracePeriod = 1,
    Expired = 2,
    Exited = 3
}
