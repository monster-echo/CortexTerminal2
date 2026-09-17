namespace CortexTerminal.Gateway.Workspaces;

using Microsoft.Extensions.Options;

/// <summary>Feedback 附件存储配置，绑定 "Feedback" 节。</summary>
public sealed class FeedbackOptions
{
    public const string SectionName = "Feedback";

    /// <summary>附件落盘根目录。Docker 部署挂载卷，如 /app/data/feedback。</summary>
    public string DataRoot { get; set; } = Path.Combine("data", "feedback");

    /// <summary>单附件字节上限。</summary>
    public long MaxFileBytes { get; set; } = 64L * 1024 * 1024;

    /// <summary>上传令牌有效期（HMAC，签名密钥复用 Auth:SigningKey）。</summary>
    public int UploadTokenTtlSeconds { get; set; } = 900;
}

/// <summary>
/// Feedback 附件的本地磁盘存储（S3 已移除）。对象名形如 "{userId}/{guid}{ext}"，
/// 由上传端点生成；读取端点做路径逃逸校验后流式回源。
/// </summary>
public sealed class FeedbackStorage(IOptions<FeedbackOptions> options)
{
    private readonly FeedbackOptions _options = options.Value;

    /// <summary>流式落盘。超过 MaxFileBytes 拒绝并删除半成品。</summary>
    public async Task SaveAsync(string objectName, Stream content, CancellationToken ct)
    {
        var path = ResolvePathOrThrow(objectName);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        var tmpPath = path + ".uploading";
        await using (var target = File.Create(tmpPath))
        {
            var buffer = new byte[64 * 1024];
            long total = 0;
            int read;
            while ((read = await content.ReadAsync(buffer, ct)) > 0)
            {
                total += read;
                if (total > _options.MaxFileBytes)
                {
                    throw new InvalidOperationException(
                        $"attachment exceeds the {_options.MaxFileBytes / (1024 * 1024)} MB limit");
                }
                await target.WriteAsync(buffer.AsMemory(0, read), ct);
            }
        }
        File.Move(tmpPath, path, overwrite: true);
    }

    public FileStream OpenRead(string objectName)
    {
        var path = ResolvePathOrThrow(objectName);
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("attachment not found", objectName);
        }
        return File.OpenRead(path);
    }

    /// <summary>拒绝路径逃逸：对象名内不允许 ".." 与盘符/根路径。</summary>
    private string ResolvePathOrThrow(string objectName)
    {
        if (string.IsNullOrEmpty(objectName)
            || objectName.Contains("..", StringComparison.Ordinal)
            || objectName.StartsWith("/", StringComparison.Ordinal)
            || objectName.Contains('\\'))
        {
            throw new InvalidOperationException("invalid attachment object name");
        }
        return Path.Combine(_options.DataRoot, objectName);
    }
}
