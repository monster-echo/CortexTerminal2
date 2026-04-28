using CortexTerminal.Gateway.Audit;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CortexTerminal.Gateway.Controllers;

[ApiController]
[Route("api/audit-log")]
public sealed class AuditLogController(IAuditLogStore auditLogStore) : ControllerBase
{
    [HttpGet]
    [Authorize]
    public IActionResult GetAuditLog(
        [FromQuery] int? page,
        [FromQuery] int? pageSize,
        [FromQuery] string? actionType,
        [FromQuery] string? userId,
        [FromQuery] DateTimeOffset? fromDate,
        [FromQuery] DateTimeOffset? toDate)
    {
        var (entries, totalCount) = auditLogStore.Query(
            page, pageSize, actionType, userId, fromDate, toDate);

        return Ok(new { entries, totalCount });
    }
}
