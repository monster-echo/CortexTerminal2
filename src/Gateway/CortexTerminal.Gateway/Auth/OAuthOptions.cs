namespace CortexTerminal.Gateway.Auth;

public sealed class OAuthOptions
{
    public OAuthProviderOptions GitHub { get; set; } = new();
    public OAuthProviderOptions Google { get; set; } = new();
}

public sealed class OAuthProviderOptions
{
    public string ClientId { get; set; } = "";
    public string ClientSecret { get; set; } = "";
}
