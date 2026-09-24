using System.Net.WebSockets;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CortexTerminal.Contracts.Streaming;

/// <summary>
/// Relay ⇄ Worker 数据面协议（原生 WebSocket，非 SignalR）。
/// 控制帧 = UTF-8 JSON 文本帧；数据帧 = 二进制帧：
/// [0x02][4 字节 requestId 长度(大端)][requestId UTF-8 字节][payload]。
/// 文件传输为每次传输一条短命 WS（/transfer/{tid}）；端口转发为每 Worker 一条持久 WS（/worker）。
/// </summary>
public static class RelayProtocol
{
    /// <summary>二进制数据帧的首字节标记，用于和误入的二进制控制区分。</summary>
    public const byte DataFrameMarker = 0x02;
    public const int RequestIdLengthBytes = 4;
    public const int DataChunkSize = 64 * 1024;

    // ── transfer WS 控制帧 type ──
    /// <summary>relay→worker：客户端 HTTP 流已接入，可以开始发送。</summary>
    public const string TransferStartType = "start";
    /// <summary>worker→relay（仅下载）：文件元信息 {"type","size","filename"}，先于任何数据帧。</summary>
    public const string FileHeadType = "filehead";
    /// <summary>worker→relay：传输终态 {"type","success","code","message"}。</summary>
    public const string TransferDoneType = "done";

    // ── tunnel 持久 WS 控制帧 type ──
    /// <summary>relay→worker：访客 HTTP 请求 {"type","id","port","method","path","query","headers"}。</summary>
    public const string TunnelRequestType = "treq";
    /// <summary>relay→worker：访客请求体结束（其后无该 id 的二进制帧）。无请求体的请求不发。</summary>
    public const string TunnelRequestBodyEndType = "treqend";
    /// <summary>worker→relay：上游响应头 {"type","id","status","headers"}。</summary>
    public const string TunnelResponseHeadType = "tres";
    /// <summary>worker→relay：请求处理终态 {"type","id","error"}。</summary>
    public const string TunnelEndType = "tend";
}

public sealed class TransferStartFrame
{
    [JsonPropertyName("type")] public string Type { get; set; } = RelayProtocol.TransferStartType;
}

public sealed class FileHeadFrame
{
    [JsonPropertyName("type")] public string Type { get; set; } = RelayProtocol.FileHeadType;
    [JsonPropertyName("size")] public long Size { get; set; }
    [JsonPropertyName("filename")] public string Filename { get; set; } = "";
}

public sealed class TransferDoneFrame
{
    [JsonPropertyName("type")] public string Type { get; set; } = RelayProtocol.TransferDoneType;
    [JsonPropertyName("success")] public bool Success { get; set; }
    [JsonPropertyName("code")] public string? Code { get; set; }
    [JsonPropertyName("message")] public string? Message { get; set; }
}

public sealed class TunnelRequestFrame
{
    [JsonPropertyName("type")] public string Type { get; set; } = RelayProtocol.TunnelRequestType;
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("port")] public int Port { get; set; }
    /// <summary>Worker 侧目标地址；旧 Relay 不下发时 worker 视为 127.0.0.1。</summary>
    [JsonPropertyName("remoteAddress")] public string? RemoteAddress { get; set; }
    [JsonPropertyName("method")] public string Method { get; set; } = "GET";
    [JsonPropertyName("path")] public string Path { get; set; } = "/";
    [JsonPropertyName("query")] public string Query { get; set; } = "";
    [JsonPropertyName("headers")] public Dictionary<string, string[]> Headers { get; set; } = new();
}

public sealed class TunnelRequestBodyEndFrame
{
    [JsonPropertyName("type")] public string Type { get; set; } = RelayProtocol.TunnelRequestBodyEndType;
    [JsonPropertyName("id")] public string Id { get; set; } = "";
}

public sealed class TunnelResponseHeadFrame
{
    [JsonPropertyName("type")] public string Type { get; set; } = RelayProtocol.TunnelResponseHeadType;
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("status")] public int Status { get; set; }
    [JsonPropertyName("headers")] public Dictionary<string, string[]> Headers { get; set; } = new();
}

public sealed class TunnelEndFrame
{
    [JsonPropertyName("type")] public string Type { get; set; } = RelayProtocol.TunnelEndType;
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("error")] public string? Error { get; set; }
}

/// <summary>
/// 数据面控制帧的源生成序列化上下文。
/// Worker 以 PublishTrimmed 发布，运行时反射序列化（JsonSerializerIsReflectionEnabledByDefault）
/// 被关闭；只有 context 绑定的 options 才能序列化这些帧,否则连接建立后第一帧就抛
/// "Reflection-based serialization has been disabled for this application"。
/// </summary>
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    PropertyNameCaseInsensitive = true)]
[JsonSerializable(typeof(TransferStartFrame))]
[JsonSerializable(typeof(FileHeadFrame))]
[JsonSerializable(typeof(TransferDoneFrame))]
[JsonSerializable(typeof(TunnelRequestFrame))]
[JsonSerializable(typeof(TunnelRequestBodyEndFrame))]
[JsonSerializable(typeof(TunnelResponseHeadFrame))]
[JsonSerializable(typeof(TunnelEndFrame))]
public partial class RelayJsonContext : JsonSerializerContext;

public static class RelayJson
{
    public static readonly JsonSerializerOptions Default = RelayJsonContext.Default.Options;
}

/// <summary>一条已组装完整的 WebSocket 帧（Worker ⇄ Relay 数据面共用）。</summary>
public readonly record struct RelayFrame(WebSocketMessageType MessageType, byte[] Data, bool EndOfMessage);
