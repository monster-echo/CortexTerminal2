namespace CortexTerminal.Gateway.Auth;

public sealed class PhoneAuthOptions
{
    public string AccessKeyId { get; set; } = "";
    public string AccessKeySecret { get; set; } = "";
    public string SignName { get; set; } = "";
    public string TemplateCode { get; set; } = "";
    public string RegionId { get; set; } = "cn-hangzhou";
}

public sealed class AppleOAuthOptions
{
    public string ClientId { get; set; } = "";
    public string TeamId { get; set; } = "";
    public string KeyId { get; set; } = "";
    public string PrivateKey { get; set; } = "";
}
