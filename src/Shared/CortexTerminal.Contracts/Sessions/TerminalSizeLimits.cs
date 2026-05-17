namespace CortexTerminal.Contracts.Sessions;

public static class TerminalSizeLimits
{
    public const int MaxColumns = 1000;
    public const int MaxRows = 1000;

    public static bool IsValid(int columns, int rows)
        => columns is > 0 and <= MaxColumns && rows is > 0 and <= MaxRows;
}
