using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class ReplayCacheTests
{
    [Fact]
    public void Append_WhenMaxBytesExceeded_EvictsOldestChunksForSession()
    {
        var cache = new ReplayCache(5);
        var oldest = new ReplayChunk("session-1", "stdout", new byte[] { 0x01, 0x02 });
        var retained = new ReplayChunk("session-1", "stdout", new byte[] { 0x03, 0x04 });
        var newest = new ReplayChunk("session-1", "stderr", new byte[] { 0x05, 0x06, 0x07 });

        cache.Append(oldest);
        cache.Append(retained);
        cache.Append(newest);

        var snapshot = cache.GetSnapshot("session-1");

        snapshot.Should().Equal(retained, newest);
        snapshot.Sum(chunk => chunk.Payload.Length).Should().BeLessThanOrEqualTo(5);
    }

    [Fact]
    public async Task Clear_WhenReplayBufferIsLocked_WaitsForSessionLockBeforeClearing()
    {
        var cache = new ReplayCache(32);
        var chunk = new ReplayChunk("session-1", "stdout", [0x01]);
        cache.Append(chunk);

        using var replayEntered = new ManualResetEventSlim();
        using var allowReplayToFinish = new ManualResetEventSlim();
        var replayTask = Task.Run(() => cache.ReplayWhileLockedAsync("session-1", _ =>
        {
            replayEntered.Set();
            allowReplayToFinish.Wait(TimeSpan.FromSeconds(1)).Should().BeTrue();
            return Task.CompletedTask;
        }, CancellationToken.None));

        replayEntered.Wait(TimeSpan.FromSeconds(1)).Should().BeTrue();

        Exception? clearFailure = null;
        using var clearFinished = new ManualResetEventSlim();
        var clearThread = new Thread(() =>
        {
            try
            {
                cache.Clear("session-1");
            }
            catch (Exception ex)
            {
                clearFailure = ex;
            }
            finally
            {
                clearFinished.Set();
            }
        });
        clearThread.Start();
        Thread.Sleep(50);
        clearFinished.IsSet.Should().BeFalse();

        allowReplayToFinish.Set();
        await replayTask;
        clearFinished.Wait(TimeSpan.FromSeconds(1)).Should().BeTrue();
        clearFailure.Should().BeNull();

        cache.GetSnapshot("session-1").Should().BeEmpty();
        GetBuffer(cache, "session-1").Should().NotBeNull();
    }

    [Fact]
    public void Append_WhenEvictionRemovesAllChunks_KeepsSessionBufferRegistered()
    {
        var cache = new ReplayCache(0);

        cache.Append(new ReplayChunk("session-1", "stdout", [0x01]));

        cache.GetSnapshot("session-1").Should().BeEmpty();
        GetBuffer(cache, "session-1").Should().NotBeNull();
    }

    private static object GetBuffer(ReplayCache cache, string sessionId)
    {
        var buffers = GetBuffers(cache);
        var tryGetValue = buffers.GetType().GetMethod("TryGetValue")!;
        var arguments = new object?[] { sessionId, null };
        var found = (bool)tryGetValue.Invoke(buffers, arguments)!;

        found.Should().BeTrue();
        return arguments[1]!;
    }

    private static object GetBuffers(ReplayCache cache)
        => typeof(ReplayCache)
            .GetField("_buffers", BindingFlags.Instance | BindingFlags.NonPublic)!
            .GetValue(cache)!;
}
