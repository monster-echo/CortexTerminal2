using CortexTerminal.Contracts;

await WorkerHost.RunAsync();

static class WorkerHost
{
    public static Task RunAsync()
    {
        var identity = new ServiceIdentity("CortexTerminal.Worker");
        Console.WriteLine($"{identity.Name} scaffold ready.");

        return Task.CompletedTask;
    }
}
