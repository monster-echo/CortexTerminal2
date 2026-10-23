using System.Text.Json;
using System.Text.Json.Serialization;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Worker.P2P;

namespace CortexTerminal.Worker.Auth;

[JsonSerializable(typeof(CortexTerminal.Worker.P2P.PunchRegisterBody))]
[JsonSerializable(typeof(DeviceFlowStartResponse))]
[JsonSerializable(typeof(DeviceFlowTokenResponse))]
[JsonSerializable(typeof(DeviceFlowPollRequest))]
[JsonSerializable(typeof(RefreshTokenResponse))]
[JsonSerializable(typeof(JsonElement))]
[JsonSerializable(typeof(TransferErrorBody))]
[JsonSerializable(typeof(TransferSuccessBody))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class WorkerJsonContext : JsonSerializerContext;

internal sealed record TransferErrorBody(string? Error, string? Message);
internal sealed record TransferSuccessBody(bool Success);
