namespace CortexTerminal.Gateway.Sessions;

public sealed class ScrollbackSettings
{
    public int MaxMegabytes { get; set; } = 5;

    public int? MaxBytesOverride { get; set; }

    public int MinAllowedBytes { get; set; } = 16 * 1024;

    public int MaxAllowedBytes { get; set; } = 5 * 1024 * 1024;

    public int MaxBytes => MaxBytesOverride ?? MaxMegabytes * 1024 * 1024;
}
