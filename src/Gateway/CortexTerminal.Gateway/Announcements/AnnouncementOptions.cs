namespace CortexTerminal.Gateway.Announcements;

/// <summary>
/// 一条客户端公告（版本通知 / 运营通知）。在 appsettings.json 的 "Announcements"
/// 数组中配置；新增通知只需追加一条并换 Id，客户端按 Id 记忆"已关闭"，每条只弹一次。
/// </summary>
public sealed class AnnouncementOptions
{
    public string Id { get; set; } = "";

    public bool Enabled { get; set; }

    public string Title { get; set; } = "";

    public string Body { get; set; } = "";

    public string ButtonLabel { get; set; } = "";

    public string Url { get; set; } = "";
}
