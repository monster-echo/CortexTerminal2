using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Workers;
using CortexTerminal.Gateway.Workspaces;
using FluentAssertions;
using Microsoft.Extensions.Options;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workspaces;

public sealed class RelayFileTransferServiceEndpointsTests
{
    private const string SharedSecret = "test-secret-for-endpoints";

    private static (RelayFileTransferService Service, PostgresWorkerRegistry Workers, WorkspaceRegistry Workspaces) NewService(
        string lanEndpoints, string? publicBaseUrl)
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "conn-1", ownerUserId: "test-user");
        workers.UpdateTransferEndpoints("worker-1",
            lanEndpoints.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries),
            publicBaseUrl);
        var workspaces = TestSessionFactory.CreateWorkspaceRegistry();

        var service = new RelayFileTransferService(
            workers,
            new CortexTerminal.Gateway.Tests.Hubs.PrepareAcceptingWorkerCommandDispatcher(),
            workspaces,
            Options.Create(new RelayOptions
            {
                SharedSecret = SharedSecret,
                PublicUrl = "https://relay.corterm.test",
            }));
        return (service, workers, workspaces);
    }

    [Fact]
    public async Task CreateUpload_LanEndpointsNoLongerAdvertised_PublicThenRelay()
    {
        // 产品决策：LAN 直连端点不再下发——手机与 worker 不同网段时必然超时，
        // 串行等待只会拖慢协商；P2P 打洞改走 workerId rendezvous。
        var (service, _, workspaces) = NewService(
            "http://192.168.1.10:47631, http://192.168.1.11:47631",
            publicBaseUrl: "https://worker.corterm.test");
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");

        var init = await service.CreateUploadAsync("test-user", ws.Id, "", "a.txt", 3, "aa", CancellationToken.None);

        init.Endpoints.Select(e => e.Kind).Should().Equal(
            [TransferEndpoint.KindPublic, TransferEndpoint.KindRelay]);
        init.Endpoints[0].Url.Should().StartWith("https://worker.corterm.test/transfer/");
        init.Endpoints.Should().OnlyContain(e => e.Url.Contains("token="));
    }

    [Fact]
    public async Task CreateUpload_WithoutDirectEndpoints_ReturnsRelayOnly()
    {
        var (service, _, workspaces) = NewService("", publicBaseUrl: null);
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");

        var init = await service.CreateUploadAsync("test-user", ws.Id, "", "a.txt", 3, "aa", CancellationToken.None);

        init.Endpoints.Should().ContainSingle();
        init.Endpoints[0].Kind.Should().Be(TransferEndpoint.KindRelay);
        init.Endpoints[0].Url.Should().StartWith("https://relay.corterm.test/transfer/");
    }

    [Fact]
    public async Task CreateUpload_EndpointToken_ValidatesAgainstSharedSecret()
    {
        var (service, _, workspaces) = NewService("", publicBaseUrl: null);
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");

        var init = await service.CreateUploadAsync("test-user", ws.Id, "", "a.txt", 3, "aa", CancellationToken.None);

        var url = init.Endpoints[0].Url;
        var tokenStart = url.IndexOf("token=") + "token=".Length;
        var tokenEnd = url.IndexOf('&', tokenStart);
        var token = tokenEnd < 0 ? url[tokenStart..] : url[tokenStart..tokenEnd];
        var transferId = init.TransferId;
        CortexTerminal.Contracts.Streaming.RelayToken
            .TryValidate(SharedSecret, token, RelayToken.AudienceTransfer, transferId, out _)
            .Should().BeTrue();
    }
}
