namespace CortexTerminal.Gateway.Support;

public sealed class SupportOptions
{
    public SupportGroupOptions QqGroup { get; set; } = new();

    public SupportGroupOptions TelegramGroup { get; set; } = new();

    public string Email { get; set; } = "";
}

public sealed class SupportGroupOptions
{
    public bool Enabled { get; set; }

    public string Name { get; set; } = "";

    public string Number { get; set; } = "";   // QQ 群号

    public string Url { get; set; } = "";       // TG t.me/xxx

    public string QrCodeUrl { get; set; } = ""; // 相对路径（/corterm_xxx.png）或绝对 URL
}
