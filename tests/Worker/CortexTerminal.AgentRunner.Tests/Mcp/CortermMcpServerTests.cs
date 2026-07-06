using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner.Mcp;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests.Mcp;

/// <summary>
/// End-to-end tests for CortermMcpServer — boots the real TcpListener on a random loopback port
/// and exercises the JSON-RPC protocol the way Claude Code's MCP client would. No mocking: the
/// goal is to catch HTTP/1.1 parsing bugs and JSON-RPC envelope regressions that unit tests on
/// the inner helpers would miss.
/// </summary>
public sealed class CortermMcpServerTests
{
    [Fact]
    public async Task StartAsync_ListensOnLoopback_UrlIs127()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        server.Url.Should().StartWith("http://127.0.0.1:");
        server.Url.Should().EndWith("/mcp");
    }

    [Fact]
    public async Task Initialize_ReturnsProtocolVersionAndToolsCapability()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var resp = await PostJsonRpcAsync(server.Url, id: 1, method: "initialize");

        resp["result"]!["protocolVersion"]!.GetValue<string>().Should().NotBeNullOrEmpty();
        resp["result"]!["capabilities"]!["tools"].Should().NotBeNull();
        resp["result"]!["serverInfo"]!["name"]!.GetValue<string>().Should().Be("corterm");
    }

    [Fact]
    public async Task ToolsList_ReturnsSingleChangeTitleTool()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var resp = await PostJsonRpcAsync(server.Url, id: 2, method: "tools/list");

        var tools = resp["result"]!["tools"]!.AsArray();
        tools.Count.Should().Be(1);
        var tool = tools[0]!.AsObject();
        tool["name"]!.GetValue<string>().Should().Be("change_title");
        tool["description"]!.GetValue<string>().Should().Contain("title");
        var required = tool["inputSchema"]!["required"]!.AsArray();
        required.Select(r => r!.GetValue<string>()).Should().ContainSingle().Which.Should().Be("title");
    }

    [Fact]
    public async Task ToolsCall_ChangeTitle_TriggersOnTitleChangedWithTrimmedTitle()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var observed = new List<string>();
        server.OnTitleChanged += (title, ct) =>
        {
            observed.Add(title);
            return Task.CompletedTask;
        };

        var resp = await PostJsonRpcAsync(
            server.Url,
            id: 3,
            method: "tools/call",
            parameters: new JsonObject
            {
                ["name"] = "change_title",
                ["arguments"] = new JsonObject { ["title"] = "  Download Bilibili Videos  " },
            });

        observed.Should().ContainSingle().Which.Should().Be("Download Bilibili Videos");
        var content = resp["result"]!["content"]!.AsArray();
        content[0]!["text"]!.GetValue<string>().Should().Contain("Download Bilibili Videos");
        resp["result"]!["isError"]!.GetValue<bool>().Should().BeFalse();
    }

    [Fact]
    public async Task ToolsCall_ChangeTitle_EmptyTitle_ReturnsErrorIsTrue()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var fired = false;
        server.OnTitleChanged += (_, _) =>
        {
            fired = true;
            return Task.CompletedTask;
        };

        var resp = await PostJsonRpcAsync(
            server.Url,
            id: 4,
            method: "tools/call",
            parameters: new JsonObject
            {
                ["name"] = "change_title",
                ["arguments"] = new JsonObject { ["title"] = "   " },
            });

        fired.Should().BeFalse();
        resp["result"]!["isError"]!.GetValue<bool>().Should().BeTrue();
    }

    [Fact]
    public async Task ToolsCall_UnknownTool_ReturnsErrorIsTrue()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var resp = await PostJsonRpcAsync(
            server.Url,
            id: 5,
            method: "tools/call",
            parameters: new JsonObject
            {
                ["name"] = "delete_everything",
                ["arguments"] = new JsonObject(),
            });

        resp["result"]!["isError"]!.GetValue<bool>().Should().BeTrue();
    }

    [Fact]
    public async Task ToolsCall_MissingArguments_ReturnsErrorIsTrue()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var resp = await PostJsonRpcAsync(
            server.Url,
            id: 6,
            method: "tools/call",
            parameters: new JsonObject { ["name"] = "change_title" });

        resp["result"]!["isError"]!.GetValue<bool>().Should().BeTrue();
    }

    [Fact]
    public async Task UnknownMethod_ReturnsMethodNotFoundError()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var resp = await PostJsonRpcAsync(server.Url, id: 7, method: "resources/list");

        resp["error"]!["code"]!.GetValue<int>().Should().Be(-32601);
    }

    [Fact]
    public async Task MalformedJson_ReturnsParseError()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var rawResp = await PostRawAsync(server.Url, "{not valid json");
        var resp = JsonNode.Parse(rawResp)!.AsObject();
        resp["error"]!["code"]!.GetValue<int>().Should().Be(-32700);
    }

    [Fact]
    public async Task NotificationsInitialized_Returns202WithEmptyBody()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);

        var (status, body) = await PostJsonRpcNotificationAsync(
            server.Url,
            method: "notifications/initialized");

        status.Should().Be(System.Net.HttpStatusCode.Accepted);
        body.Should().BeEmpty();
    }

    [Fact]
    public async Task StopAsync_ReleasesPort()
    {
        var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);
        var url = server.Url;

        await server.StopAsync();

        var act = async () =>
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromMilliseconds(500) };
            await client.PostAsync(url, new StringContent("{}", Encoding.UTF8));
        };
        await act.Should().ThrowAsync<HttpRequestException>();
    }

    [Fact]
    public async Task ToolsCall_HandlerThrows_ReturnsErrorIsTrueWithExceptionMessage()
    {
        await using var server = new CortermMcpServer();
        await server.StartAsync(CancellationToken.None);
        server.OnTitleChanged += (_, _) => throw new InvalidOperationException("boom");

        var resp = await PostJsonRpcAsync(
            server.Url,
            id: 8,
            method: "tools/call",
            parameters: new JsonObject
            {
                ["name"] = "change_title",
                ["arguments"] = new JsonObject { ["title"] = "anything" },
            });

        resp["result"]!["isError"]!.GetValue<bool>().Should().BeTrue();
        var text = resp["result"]!["content"]!.AsArray()[0]!["text"]!.GetValue<string>();
        text.Should().Contain("boom");
    }

    private static async Task<JsonObject> PostJsonRpcAsync(
        string url,
        int id,
        string method,
        JsonObject? parameters = null)
    {
        var body = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id,
            ["method"] = method,
        };
        if (parameters is not null) body["params"] = parameters;

        var raw = await PostRawAsync(url, body.ToJsonString());
        return JsonNode.Parse(raw)!.AsObject();
    }

    private static async Task<(System.Net.HttpStatusCode status, string body)> PostJsonRpcNotificationAsync(
        string url,
        string method)
    {
        var body = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["method"] = method,
        };
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        using var content = new StringContent(body.ToJsonString(), Encoding.UTF8);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        using var resp = await client.PostAsync(url, content);
        var respBody = await resp.Content.ReadAsStringAsync();
        return (resp.StatusCode, respBody);
    }

    private static async Task<string> PostRawAsync(string url, string body)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        using var content = new StringContent(body, Encoding.UTF8);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        using var resp = await client.PostAsync(url, content);
        return await resp.Content.ReadAsStringAsync();
    }
}
