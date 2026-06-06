namespace CortexTerminal.Gateway.Tts;

public sealed class TtsOptions
{
    public CloudflareTtsOptions Cloudflare { get; set; } = new();
    public AliyunTtsOptions Aliyun { get; set; } = new();
}

public sealed class CloudflareTtsOptions
{
    public string AccountId { get; set; } = "";
    public string ApiToken { get; set; } = "";
}

public sealed class AliyunTtsOptions
{
    public string ApiKey { get; set; } = "";
    public string Model { get; set; } = "cosyvoice-v2";
    public string Voice { get; set; } = "longxiaochun";
}
