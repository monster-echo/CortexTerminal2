await WorkerHost.RunAsync();

static class WorkerHost
{
    public static Task RunAsync()
    {
        Console.WriteLine("CortexTerminal.Worker scaffold ready.");

        return Task.CompletedTask;
    }
}
