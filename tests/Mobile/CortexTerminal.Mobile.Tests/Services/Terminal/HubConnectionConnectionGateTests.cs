using CortexTerminal.Mobile.Services.Terminal;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR.Client;

namespace CortexTerminal.Mobile.Tests.Services.Terminal;

public sealed class HubConnectionConnectionGateTests
{
    [Fact]
    public async Task EnsureConnectedAsync_StartsWhenDisconnected()
    {
        var state = HubConnectionState.Disconnected;
        var starts = 0;

        await HubConnectionConnectionGate.EnsureConnectedAsync(
            () => state,
            async cancellationToken =>
            {
                starts++;
                await Task.Delay(10, cancellationToken);
                state = HubConnectionState.Connected;
            },
            CancellationToken.None);

        starts.Should().Be(1);
    }

    [Fact]
    public async Task EnsureConnectedAsync_WaitsWhileConnecting()
    {
        var state = HubConnectionState.Connecting;
        var starts = 0;
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));

        var completion = HubConnectionConnectionGate.EnsureConnectedAsync(
            () => state,
            cancellationToken =>
            {
                starts++;
                state = HubConnectionState.Connected;
                return Task.CompletedTask;
            },
            cts.Token);

        await Task.Delay(100, CancellationToken.None);
        state = HubConnectionState.Connected;

        await completion;

        starts.Should().Be(0);
    }

    [Fact]
    public async Task EnsureConnectedAsync_WaitsWhileReconnecting()
    {
        var state = HubConnectionState.Reconnecting;
        var starts = 0;
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));

        var completion = HubConnectionConnectionGate.EnsureConnectedAsync(
            () => state,
            cancellationToken =>
            {
                starts++;
                state = HubConnectionState.Connected;
                return Task.CompletedTask;
            },
            cts.Token);

        await Task.Delay(100, CancellationToken.None);
        state = HubConnectionState.Disconnected;

        await completion;

        starts.Should().Be(1);
    }

    [Fact]
    public async Task EnsureConnectedAsync_RespectsCancellationWhileWaiting()
    {
        var state = HubConnectionState.Reconnecting;
        using var cts = new CancellationTokenSource();

        var waitTask = HubConnectionConnectionGate.EnsureConnectedAsync(
            () => state,
            _ => Task.CompletedTask,
            cts.Token);

        cts.CancelAfter(100);

        await FluentActions.Awaiting(() => waitTask).Should().ThrowAsync<OperationCanceledException>();
    }
}
