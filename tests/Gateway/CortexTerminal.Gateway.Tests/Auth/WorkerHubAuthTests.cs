using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Http.Connections;
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

    [Fact]
    public async Task WorkerHub_SetsOwnerUserId_FromToken()
    {
        // Register worker via authenticated SignalR connection
        var connection = _factory.CreateAuthenticatedHubConnection("/hubs/worker");
        try
        {
            await connection.StartAsync();
            await connection.InvokeAsync("RegisterWorker", "worker-owned");

            // Query the worker via REST API to check ownership
            using var client = _factory.CreateAuthenticatedClient();
            using var response = await client.GetAsync("/api/me/workers");

            response.StatusCode.Should().Be(HttpStatusCode.OK);
            var workers = await response.Content.ReadFromJsonAsync<JsonElement>();
            workers.ValueKind.Should().Be(JsonValueKind.Array);

            // The "test-user" from GatewayApplicationFactory.CreateAccessToken should own this worker
            var found = false;
            foreach (var w in workers.EnumerateArray())
            {
                if (w.TryGetProperty("workerId", out var id) && id.GetString() == "worker-owned")
                {
                    found = true;
                    break;
                }
            }

            found.Should().BeTrue("worker-owned should appear in user's worker list");
        }
        finally
        {
            await connection.DisposeAsync();
        }
    }
}
