namespace CortexTerminal.Contracts;

public interface IServiceIdentity
{
    string Name { get; }
}

public sealed record ServiceIdentity(string Name) : IServiceIdentity;
