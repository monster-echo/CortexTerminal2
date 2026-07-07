namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Resolves the remote Corterm agent-skill source URLs and fetches the latest
/// <c>SKILL.md</c> / <c>CODEX.md</c>. The source lives in the CortexTerminal2 repo under
/// <c>skills/corterm-artifacts/</c> and is pulled via the GitHub proxy (prefix-style, same
/// convention as the worker <c>update</c> command at <c>Program.cs</c> download step) so it
/// works behind the GFW without extra setup.
///
/// <para>Override knobs (env vars):</para>
/// <list type="bullet">
/// <item><c>CORTERM_GITHUB_PROXY</c> — prefix-style proxy (default <c>https://proxy.0x2a.top</c>).</item>
/// <item><c>CORTERM_SKILL_REF</c> — git ref to pull (default <c>main</c>; pin a tag/commit to lock or roll back).</item>
/// <item><c>CORTERM_SKILL_SOURCE_URL</c> — fully overrides the base URL (point at your own
/// mirror/object store); no proxy prefix is applied in this mode.</item>
/// </list>
/// </summary>
internal sealed class AgentSkillSource
{
    private const string DefaultRepo = "monster-echo/CortexTerminal2";
    private const string DefaultRef = "main";
    private const string DefaultProxy = "https://proxy.0x2a.top";
    private const string SkillPath = "skills/corterm-artifacts";
    private static readonly TimeSpan FetchTimeout = TimeSpan.FromSeconds(5);

    private readonly string _skillMdUrl;
    private readonly string _codexMdUrl;

    public AgentSkillSource()
    {
        var proxy = Environment.GetEnvironmentVariable("CORTERM_GITHUB_PROXY");
        if (string.IsNullOrWhiteSpace(proxy)) proxy = DefaultProxy;
        proxy = proxy.TrimEnd('/');

        var refOrTag = Environment.GetEnvironmentVariable("CORTERM_SKILL_REF");
        if (string.IsNullOrWhiteSpace(refOrTag)) refOrTag = DefaultRef;

        var explicitBase = Environment.GetEnvironmentVariable("CORTERM_SKILL_SOURCE_URL");
        if (!string.IsNullOrWhiteSpace(explicitBase))
        {
            // Full override: point both files at the user-supplied base with no proxy prefix.
            var baseUri = explicitBase.TrimEnd('/');
            _skillMdUrl = baseUri + "/SKILL.md";
            _codexMdUrl = baseUri + "/CODEX.md";
        }
        else
        {
            var rawBase = $"https://raw.githubusercontent.com/{DefaultRepo}/{refOrTag}/{SkillPath}";
            // Prefix-style proxy: <proxy>/<original-url> — same shape as Program.cs release download.
            _skillMdUrl = $"{proxy}/{rawBase}/SKILL.md";
            _codexMdUrl = $"{proxy}/{rawBase}/CODEX.md";
        }
    }

    public string SkillMdUrl => _skillMdUrl;
    public string CodexMdUrl => _codexMdUrl;

    /// <summary>
    /// Fetch both files. Throws on network/timeout failure — the caller decides whether to fall
    /// back to the local cache. Uses a 5 s timeout independent of the caller's cancellation token
    /// so a hung remote cannot stall worker startup.
    /// </summary>
    public async Task<(string SkillMd, string CodexMd)> FetchAsync(HttpClient http, CancellationToken cancellationToken)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(FetchTimeout);
        var skillMd = await http.GetStringAsync(_skillMdUrl, cts.Token);
        var codexMd = await http.GetStringAsync(_codexMdUrl, cts.Token);
        return (skillMd, codexMd);
    }
}
