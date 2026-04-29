using System.Text.Json;
using System.Text.Json.Serialization;
using CortexTerminal.Contracts.Auth;

namespace CortexTerminal.Worker.Auth;

[JsonSerializable(typeof(DeviceFlowStartResponse))]
[JsonSerializable(typeof(DeviceFlowTokenResponse))]
[JsonSerializable(typeof(DeviceFlowPollRequest))]
[JsonSerializable(typeof(JsonElement))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class WorkerJsonContext : JsonSerializerContext;
