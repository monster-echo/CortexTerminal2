using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

/// <summary>工作区：Worker 上的命名根目录。Session 绑定工作区，文件管理以工作区为边界。</summary>
public class WorkspaceEntity
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = "";

    [Required]
    [Column("owner_user_id")]
    public string OwnerUserId { get; set; } = "";

    [Required]
    [Column("worker_id")]
    [StringLength(64)]
    public string WorkerId { get; set; } = "";

    [Required]
    [Column("name")]
    [StringLength(100)]
    public string Name { get; set; } = "";

    /// <summary>Worker 解析后的绝对路径。Worker 端强制路径包含于该根内。</summary>
    [Required]
    [Column("root_path")]
    [StringLength(512)]
    public string RootPath { get; set; } = "";

    /// <summary>默认工作区（Worker 首次注册时按其 home 自动创建）不可删除。</summary>
    [Required]
    [Column("is_default")]
    public bool IsDefault { get; set; }

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; }

    [Column("deleted_at_utc")]
    public DateTimeOffset? DeletedAtUtc { get; set; }
}
