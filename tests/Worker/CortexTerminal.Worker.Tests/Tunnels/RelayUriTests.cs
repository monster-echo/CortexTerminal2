using System;
using System.Collections.Generic;
using CortexTerminal.Contracts.Streaming;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Tunnels;

/// <summary>
/// RelayUri：Relay 公网地址是 http(s) 形态，但 WS 连接只接受 ws(s)。
/// 隧道与文件传输都曾因为直接拼 http:// 给 ClientWebSocket 而连不上。
/// </summary>
public sealed class RelayUriTests
{
    [Theory]
    [InlineData("http://localhost:8090", "ws", 8090)]
    [InlineData("https://relay.example.com", "wss", 443)]
    [InlineData("ws://localhost:8090", "ws", 8090)]
    [InlineData("wss://relay.example.com:9443/", "wss", 9443)]
    public void BuildWebSocketUri_MapsScheme(string relayUrl, string scheme, int port)
    {
        var uri = RelayUri.BuildWebSocketUri(
            relayUrl,
            "transfer/abc123/worker",
            new KeyValuePair<string, string>("token", "t k"));

        uri.Scheme.Should().Be(scheme);
        uri.Port.Should().Be(port);
        uri.AbsolutePath.Should().Be("/transfer/abc123/worker");
        uri.Query.Should().Be("?token=t%20k");
    }

    [Fact]
    public void BuildWebSocketUri_WithoutQueryHasNoQueryString()
    {
        var uri = RelayUri.BuildWebSocketUri("http://localhost:8090", "/worker");
        uri.Query.Should().BeEmpty();
    }

    [Fact]
    public void BuildWebSocketUri_ToleratesTrailingSlashAndLeadingSlash()
    {
        var uri = RelayUri.BuildWebSocketUri("http://localhost:8090/", "/transfer/x/worker");
        uri.AbsolutePath.Should().Be("/transfer/x/worker");
    }
}