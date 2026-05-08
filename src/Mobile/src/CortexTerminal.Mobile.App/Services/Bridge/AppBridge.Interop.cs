using System.Security.Cryptography;
using System.Text.Json;
using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.Core.Bridge.Models;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    [BridgeMethod]
    public async Task<string> StartBinaryStreamToJsAsync(int chunkByteLength = 256, int chunkCount = 20, int intervalMs = 250)
    {
        var normalizedChunkByteLength = Math.Clamp(chunkByteLength, 8, 16 * 1024);
        var normalizedChunkCount = Math.Clamp(chunkCount, 1, 200);
        var normalizedIntervalMs = Math.Clamp(intervalMs, 16, 2_000);
        var streamId = Guid.NewGuid().ToString("N");
        CancellationTokenSource cts;

        lock (_binaryStreamSyncRoot)
        {
            _binaryStreamCts?.Cancel();
            _binaryStreamCts?.Dispose();
            _binaryStreamCts = new CancellationTokenSource();
            cts = _binaryStreamCts;
        }

        _ = Task.Run(() => RunBinaryStreamAsync(
            streamId,
            normalizedChunkByteLength,
            normalizedChunkCount,
            normalizedIntervalMs,
            cts.Token));

        await SendEventToWebViewAsync(new
        {
            type = "bridgeStream.started",
            source = "csharp",
            streamId,
            chunkByteLength = normalizedChunkByteLength,
            chunkCount = normalizedChunkCount,
            intervalMs = normalizedIntervalMs,
            startedAt = DateTimeOffset.UtcNow,
        }, "bridge stream started");

        return JsonSerializer.Serialize(new { success = true }, _jsonOptions);
    }

    [BridgeMethod]
    public async Task<string> StopBinaryStreamToJsAsync()
    {
        CancellationTokenSource? cts;

        lock (_binaryStreamSyncRoot)
        {
            cts = _binaryStreamCts;
            _binaryStreamCts = null;
        }

        if (cts is null)
        {
            await SendEventToWebViewAsync(new
            {
                type = "bridgeStream.stopped",
                source = "csharp",
                reason = "idle",
                stoppedAt = DateTimeOffset.UtcNow,
            }, "bridge stream idle stop");

            return JsonSerializer.Serialize(new { success = true }, _jsonOptions);
        }

        cts.Cancel();
        cts.Dispose();

        return JsonSerializer.Serialize(new { success = true }, _jsonOptions);
    }

    [BridgeMethod]
    public Task<string> EchoTextAsync(string message)
    {
        return ExecuteSafeAsync(() => Task.FromResult(new
        {
            source = "csharp",
            message,
            length = message?.Length ?? 0,
            receivedAt = DateTimeOffset.UtcNow,
        }));
    }

    [BridgeMethod]
    public Task<string> EchoBinaryAsync(string base64)
    {
        return ExecuteSafeAsync(() =>
        {
            var bytes = string.IsNullOrWhiteSpace(base64)
                ? Array.Empty<byte>()
                : Convert.FromBase64String(base64);

            return Task.FromResult(new
            {
                source = "csharp",
                byteLength = bytes.Length,
                checksum = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(),
                base64 = Convert.ToBase64String(bytes),
            });
        });
    }

    [BridgeMethod]
    public Task<string> SendTextMessageToJsAsync(string message)
    {
        return ExecuteSafeVoidAsync(() => SendEventToWebViewAsync(new
        {
            type = "bridgeDemo.text",
            source = "csharp",
            text = message,
            sentAt = DateTimeOffset.UtcNow,
        }, "bridge text message"));
    }

    [BridgeMethod]
    public Task<string> HelloAsync()
    {
        return ExecuteSafeAsync(() => Task.FromResult(new { message = "world" }));
    }

    [BridgeMethod]
    public Task<string> GreetAsync(GreetingRequest request)
    {
        return ExecuteSafeAsync(() =>
        {
            var greeting = request.Language?.ToLowerInvariant() switch
            {
                "zh" => $"你好，{request.Name}！",
                "ja" => $"こんにちは、{request.Name}さん！",
                "ko" => $"안녕하세요, {request.Name}님!",
                "fr" => $"Bonjour, {request.Name} !",
                "es" => $"¡Hola, {request.Name}!",
                _ => $"Hello, {request.Name}!",
            };

            return Task.FromResult(new GreetingResponse
            {
                Greeting = greeting,
                Name = request.Name,
                Language = request.Language ?? "en",
                Timestamp = DateTimeOffset.UtcNow.ToString("O"),
                WordCount = greeting.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length,
            });
        });
    }

    [BridgeMethod]
    public Task<string> SendBinaryMessageToJsAsync(int byteLength = 32)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            var normalizedLength = Math.Clamp(byteLength, 1, 4096);
            var bytes = Enumerable.Range(0, normalizedLength)
                .Select(index => (byte)(index % 256))
                .ToArray();

            return SendEventToWebViewAsync(new
            {
                type = "bridgeDemo.binary",
                source = "csharp",
                byteLength = bytes.Length,
                checksum = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(),
                base64 = Convert.ToBase64String(bytes),
                sentAt = DateTimeOffset.UtcNow,
            }, "bridge binary message");
        });
    }

    private async Task RunBinaryStreamAsync(
        string streamId,
        int chunkByteLength,
        int chunkCount,
        int intervalMs,
        CancellationToken cancellationToken)
    {
        try
        {
            for (var sequence = 0; sequence < chunkCount; sequence += 1)
            {
                cancellationToken.ThrowIfCancellationRequested();

                var bytes = CreateBinaryStreamChunk(chunkByteLength, sequence);
                await SendEventToWebViewAsync(new
                {
                    type = "bridgeStream.chunk",
                    source = "csharp",
                    streamId,
                    sequence,
                    chunkCount,
                    byteLength = bytes.Length,
                    checksum = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(),
                    base64 = Convert.ToBase64String(bytes),
                    sentAt = DateTimeOffset.UtcNow,
                }, "bridge stream chunk");

                if (sequence < chunkCount - 1)
                {
                    await Task.Delay(intervalMs, cancellationToken);
                }
            }

            await SendEventToWebViewAsync(new
            {
                type = "bridgeStream.completed",
                source = "csharp",
                streamId,
                chunkCount,
                chunkByteLength,
                completedAt = DateTimeOffset.UtcNow,
            }, "bridge stream completed");
        }
        catch (OperationCanceledException)
        {
            await SendEventToWebViewAsync(new
            {
                type = "bridgeStream.stopped",
                source = "csharp",
                streamId,
                reason = "cancelled",
                stoppedAt = DateTimeOffset.UtcNow,
            }, "bridge stream stopped");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to stream binary data to JS.");
            await SendEventToWebViewAsync(new
            {
                type = "bridgeStream.error",
                source = "csharp",
                streamId,
                message = ex.Message,
                failedAt = DateTimeOffset.UtcNow,
            }, "bridge stream error");
        }
        finally
        {
            lock (_binaryStreamSyncRoot)
            {
                if (_binaryStreamCts?.Token == cancellationToken)
                {
                    _binaryStreamCts?.Dispose();
                    _binaryStreamCts = null;
                }
            }
        }
    }

    private static byte[] CreateBinaryStreamChunk(int chunkByteLength, int sequence)
    {
        var bytes = new byte[chunkByteLength];
        for (var index = 0; index < bytes.Length; index += 1)
        {
            bytes[index] = (byte)((sequence * 31 + index) % 256);
        }

        return bytes;
    }
}