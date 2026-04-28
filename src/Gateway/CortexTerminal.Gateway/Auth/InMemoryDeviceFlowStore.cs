using System.Collections.Concurrent;

namespace CortexTerminal.Gateway.Auth;

public sealed class DeviceFlowPendingRequest
{
    public string DeviceCode { get; init; } = "";
    public string UserCode { get; init; } = "";
    public DateTimeOffset ExpiresAtUtc { get; init; }
    public string? OwnerUserId { get; set; }
    public string? OwnerUsername { get; set; }
    public bool Confirmed { get; set; }
}

public sealed class InMemoryDeviceFlowStore
{
    private readonly ConcurrentDictionary<string, DeviceFlowPendingRequest> _byDeviceCode = new();
    private readonly ConcurrentDictionary<string, DeviceFlowPendingRequest> _byUserCode = new();

    private static readonly char[] CodeChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".ToCharArray();

    public DeviceFlowPendingRequest Create(int expiresInSeconds = 900)
    {
        RemoveExpired();

        string deviceCode;
        string userCode;
        DeviceFlowPendingRequest request;

        do
        {
            deviceCode = Guid.NewGuid().ToString("N");
            userCode = GenerateUserCode();
            request = new DeviceFlowPendingRequest
            {
                DeviceCode = deviceCode,
                UserCode = userCode,
                ExpiresAtUtc = DateTimeOffset.UtcNow.AddSeconds(expiresInSeconds)
            };
        }
        while (!_byDeviceCode.TryAdd(deviceCode, request));

        _byUserCode[userCode] = request;

        return request;
    }

    public bool TryGetByDeviceCode(string deviceCode, out DeviceFlowPendingRequest? request)
    {
        return _byDeviceCode.TryGetValue(deviceCode, out request);
    }

    public bool TryGetByUserCode(string userCode, out DeviceFlowPendingRequest? request)
    {
        return _byUserCode.TryGetValue(userCode, out request);
    }

    public bool Confirm(string userCode, string userId, string username)
    {
        if (!_byUserCode.TryGetValue(userCode, out var request))
            return false;

        if (request.ExpiresAtUtc < DateTimeOffset.UtcNow)
            return false;

        request.OwnerUserId = userId;
        request.OwnerUsername = username;
        request.Confirmed = true;

        return true;
    }

    public void Remove(string deviceCode)
    {
        if (_byDeviceCode.TryRemove(deviceCode, out var request))
        {
            _byUserCode.TryRemove(request.UserCode, out _);
        }
    }

    private void RemoveExpired()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var kvp in _byDeviceCode)
        {
            if (kvp.Value.ExpiresAtUtc < now)
            {
                _byDeviceCode.TryRemove(kvp.Key, out _);
                _byUserCode.TryRemove(kvp.Value.UserCode, out _);
            }
        }
    }

    private static string GenerateUserCode()
    {
        return string.Create(9, (object?)null, (span, _) =>
        {
            for (var i = 0; i < 9; i++)
            {
                if (i == 4)
                {
                    span[i] = '-';
                }
                else
                {
                    span[i] = CodeChars[Random.Shared.Next(CodeChars.Length)];
                }
            }
        });
    }
}
