using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;

namespace CortexTerminal.AgentRunner.Sinks;

/// <summary>
/// Forwards events to the Worker's loopback HTTP endpoint via POST. Same wire format and 10s
/// timeout as the original HookForwarder.PostEnvelope — extracted here so the sink chain can
/// compose File + HTTP without HookForwarder knowing about HTTP specifics.
///
/// <para>
/// Returns the response body so HookForwarder can write it to stdout. Claude Code's
/// <c>UserPromptSubmit</c> hook reads stdout as JSON (<c>hookSpecificOutput.additionalContext</c>)
/// and merges it into the upcoming turn's context — this is the channel the Worker uses to tell
/// Claude Code about files uploaded via the Console.
/// </para>
/// </summary>
internal sealed class HttpSink : IAgentEventSink
{
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(10) };

    private readonly string _hookUrl;

    public HttpSink(string hookUrl)
    {
        if (string.IsNullOrEmpty(hookUrl)) throw new ArgumentException("hookUrl must not be empty", nameof(hookUrl));
        _hookUrl = hookUrl;
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    public async Task<string> ForwardAsync(string envelopeJson, CancellationToken ct)
    {
        using var content = new StringContent(envelopeJson, Encoding.UTF8);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        using var resp = await HttpClient.PostAsync(_hookUrl, content, ct);
        if (!resp.IsSuccessStatusCode && resp.StatusCode != System.Net.HttpStatusCode.Accepted)
        {
            throw new HttpRequestException($"POST {_hookUrl} returned {(int)resp.StatusCode} {resp.ReasonPhrase}");
        }
        return await resp.Content.ReadAsStringAsync(ct);
    }
}
