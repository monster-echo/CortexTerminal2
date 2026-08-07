using System.Text.Json.Nodes;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests;

/// <summary>
/// Shapes for the <c>corterm --json</c> output builders. These are the contracts the worker
/// desktop UI parses, so locking the field names/types here guards against drift.
/// </summary>
public sealed class CliJsonTests
{
    [Fact]
    public void Status_EmitAndRoundTrip_AllFieldsPresent()
    {
        var workers = new JsonArray();
        workers.Add((JsonNode)CliJson.Worker("w1", "box", "host1", "osx", "arm64", "0.5.13", true, "2026-08-01T00:00:00Z", 2, 12.5, 40.0));
        var gatewayInfo = new JsonObject { ["version"] = "1.2.3", ["latestWorkerVersion"] = "0.5.14" };

        var obj = CliJson.Status("0.5.13", 1234, "1d 2h 3m", "https://corterm.rwecho.top", "worker-host",
            authenticated: true, "alice", "expires in 1d", gatewayInfo, updateAvailable: true, workers);

        var node = JsonNode.Parse(obj.ToJsonString())!.AsObject();
        node["version"]!.GetValue<string>().Should().Be("0.5.13");
        node["pid"]!.GetValue<int>().Should().Be(1234);
        node["uptime"]!.GetValue<string>().Should().Be("1d 2h 3m");
        node["gateway"]!.GetValue<string>().Should().Be("https://corterm.rwecho.top");
        node["workerId"]!.GetValue<string>().Should().Be("worker-host");
        node["authenticated"]!.GetValue<bool>().Should().BeTrue();
        node["user"]!.GetValue<string>().Should().Be("alice");
        node["authExpiry"]!.GetValue<string>().Should().Be("expires in 1d");
        node["updateAvailable"]!.GetValue<bool>().Should().BeTrue();
        node["gatewayInfo"]!.AsObject()["latestWorkerVersion"]!.GetValue<string>().Should().Be("0.5.14");

        var w = node["workers"]!.AsArray()[0]!.AsObject();
        w["workerId"]!.GetValue<string>().Should().Be("w1");
        w["isOnline"]!.GetValue<bool>().Should().BeTrue();
        w["sessionCount"]!.GetValue<int>().Should().Be(2);
        w["cpuUsagePercent"]!.GetValue<double>().Should().Be(12.5);
    }

    [Fact]
    public void Status_NotAuthenticated_NullsAndEmptyWorkers()
    {
        var obj = CliJson.Status("0.5.13", 1, "n/a", "https://g", "w", false, null, null, null, false, new JsonArray());
        var node = JsonNode.Parse(obj.ToJsonString())!.AsObject();
        node["authenticated"]!.GetValue<bool>().Should().BeFalse();
        node["user"].Should().BeNull();          // JSON null
        node["gatewayInfo"].Should().BeNull();   // JSON null
        node["workers"]!.AsArray().Should().BeEmpty();
    }

    [Fact]
    public void Doctor_PassedAndFailedCountsReflectChecks()
    {
        var checks = new List<(string Name, bool Ok, string Detail)>
        {
            ("Gateway URL", true, "https://g"),
            ("Gateway reachable", true, "latency: 5ms"),
            ("Auth token present", false, "missing"),
        };

        var node = JsonNode.Parse(CliJson.Doctor(checks).ToJsonString())!.AsObject();
        node["passedCount"]!.GetValue<int>().Should().Be(2);
        node["failedCount"]!.GetValue<int>().Should().Be(1);
        var checksArr = node["checks"]!.AsArray();
        checksArr.Count.Should().Be(3);
        checksArr[2]!.AsObject()["name"]!.GetValue<string>().Should().Be("Auth token present");
        checksArr[2]!.AsObject()["ok"]!.GetValue<bool>().Should().BeFalse();
    }

    [Fact]
    public void UpdateCheck_LatestAndAvailability()
    {
        var node = JsonNode.Parse(CliJson.UpdateCheck("0.5.13", "0.5.14", true, "corterm-osx-arm64.tar.gz", "https://dl").ToJsonString())!.AsObject();
        node["currentVersion"]!.GetValue<string>().Should().Be("0.5.13");
        node["latestVersion"]!.GetValue<string>().Should().Be("0.5.14");
        node["updateAvailable"]!.GetValue<bool>().Should().BeTrue();
        node["assetName"]!.GetValue<string>().Should().Be("corterm-osx-arm64.tar.gz");
        node["downloadUrl"]!.GetValue<string>().Should().Be("https://dl");
    }

    [Fact]
    public void Service_SuccessAndError()
    {
        var ok = JsonNode.Parse(CliJson.Service("start", true, "Worker started.").ToJsonString())!.AsObject();
        ok["action"]!.GetValue<string>().Should().Be("start");
        ok["ok"]!.GetValue<bool>().Should().BeTrue();
        ok["error"].Should().BeNull();           // JSON null

        var err = JsonNode.Parse(CliJson.Service("restart", false, "", "Failed to restart worker (exit code 1).").ToJsonString())!.AsObject();
        err["ok"]!.GetValue<bool>().Should().BeFalse();
        err["error"]!.GetValue<string>().Should().Contain("exit code 1");
    }

    [Fact]
    public void LoginStage_CodeAndSuccess()
    {
        var code = JsonNode.Parse(CliJson.LoginStage("code", "https://corterm.rwecho.top/device", "ABCD-EFGH", 900, 5).ToJsonString())!.AsObject();
        code["stage"]!.GetValue<string>().Should().Be("code");
        code["userCode"]!.GetValue<string>().Should().Be("ABCD-EFGH");
        code["expiresInSeconds"]!.GetValue<int>().Should().Be(900);
        code["pollIntervalSeconds"]!.GetValue<int>().Should().Be(5);

        var done = JsonNode.Parse(CliJson.LoginStage("success").ToJsonString())!.AsObject();
        done["stage"]!.GetValue<string>().Should().Be("success");
    }

    [Fact]
    public void UpdateStage_DownloadBytesAndError()
    {
        var dl = JsonNode.Parse(CliJson.UpdateStage("download", bytes: 2048, message: "corterm-osx-arm64.tar.gz").ToJsonString())!.AsObject();
        dl["stage"]!.GetValue<string>().Should().Be("download");
        dl["bytes"]!.GetValue<long>().Should().Be(2048);

        var err = JsonNode.Parse(CliJson.UpdateStage("error", message: "boom").ToJsonString())!.AsObject();
        err["stage"]!.GetValue<string>().Should().Be("error");
        err["message"]!.GetValue<string>().Should().Be("boom");
    }
}
