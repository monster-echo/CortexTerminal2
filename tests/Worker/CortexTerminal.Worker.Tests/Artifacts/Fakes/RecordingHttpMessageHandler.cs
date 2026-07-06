using System.Net;

namespace CortexTerminal.Worker.Tests.Artifacts.Fakes;

/// <summary>
/// HttpMessageHandler that records every request and lets each test dial in the response
/// (status code, body, delay, exception) via <see cref="Responder"/>.
/// </summary>
internal sealed class RecordingHttpMessageHandler : HttpMessageHandler
{
    public List<HttpRequestMessage> Requests { get; } = [];
    public List<(string Url, byte[] Body)> Puts { get; } = [];

    /// <summary>
    /// Per-request responder. Default returns 200 OK with empty body.
    /// Throw an exception inside to simulate a transport failure.
    /// </summary>
    public Func<HttpRequestMessage, HttpResponseMessage>? Responder { get; set; }

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(CloneRequest(request));
        if (request.Method == HttpMethod.Put && request.Content is not null)
        {
            var bytes = request.Content.ReadAsByteArrayAsync(cancellationToken).GetAwaiter().GetResult();
            Puts.Add((request.RequestUri?.ToString() ?? string.Empty, bytes));
        }

        var resp = Responder?.Invoke(request) ?? new HttpResponseMessage(HttpStatusCode.OK);
        return Task.FromResult(resp);
    }

    private static HttpRequestMessage CloneRequest(HttpRequestMessage request)
    {
        // Tests only inspect method/URI; we don't reuse the body after the handler returns.
        var clone = new HttpRequestMessage(request.Method, request.RequestUri);
        foreach (var header in request.Headers)
        {
            clone.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }
        return clone;
    }
}
