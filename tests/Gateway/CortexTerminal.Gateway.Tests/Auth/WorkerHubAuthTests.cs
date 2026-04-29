using FluentAssertions;
using Microsoft.AspNetCore.SignalR.Client;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class WorkerHubAuthTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public WorkerHubAuthTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task WorkerHub_RejectsUnauthenticatedConnection()
    {
        var connection = _factory.CreateHubConnection("/hubs/worker");
        try
        {
            // Unauthenticated connections should fail when starting or invoking
            var exception = await Record.ExceptionAsync(async () =>
            {
                await connection.StartAsync();
                await connection.InvokeAsync("RegisterWorker", "test-worker");
            });

            exception.Should().NotBeNull("unauthenticated connections should be rejected");
        }
        finally
        {
            await connection.DisposeAsync();
        }
    }

    [Fact]
    public async Task WorkerHub_AcceptsAuthenticatedConnection()
    {
        var connection = _factory.CreateAuthenticatedHubConnection("/hubs/worker");
        try
        {
            await connection.StartAsync();
            // Should succeed without throwing
            await connection.InvokeAsync("RegisterWorker", "test-worker-authenticated");
        }
        finally
        {
            await connection.DisposeAsync();
        }
    }

}
