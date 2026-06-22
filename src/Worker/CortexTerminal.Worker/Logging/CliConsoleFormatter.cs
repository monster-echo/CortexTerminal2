using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Logging.Console;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Worker.Logging;

public sealed class CliConsoleFormatter : ConsoleFormatter, IDisposable
{
    private readonly IDisposable? _optionsReloadToken;
    private SimpleConsoleFormatterOptions _options;

    public CliConsoleFormatter(IOptionsMonitor<SimpleConsoleFormatterOptions> options)
        : base("cli")
    {
        _options = options.CurrentValue;
        _optionsReloadToken = options.OnChange(opts => _options = opts);
    }

    public void Dispose() => _optionsReloadToken?.Dispose();

    private static string GetLevelLabel(LogLevel level) => level switch
    {
        LogLevel.Trace => "TRC",
        LogLevel.Debug => "DBG",
        LogLevel.Information => "INF",
        LogLevel.Warning => "WRN",
        LogLevel.Error => "ERR",
        LogLevel.Critical => "CRT",
        _ => "???"
    };

    private static string GetLevelColor(LogLevel level) => level switch
    {
        LogLevel.Warning => "\x1b[33m",
        LogLevel.Error => "\x1b[31m",
        LogLevel.Critical => "\x1b[1;31m",
        _ => ""
    };

    public override void Write<TState>(in LogEntry<TState> logEntry, IExternalScopeProvider? scopeProvider, TextWriter textWriter)
    {
        var colorEnabled = _options.ColorBehavior == LoggerColorBehavior.Enabled
            || (_options.ColorBehavior == LoggerColorBehavior.Default && !Console.IsOutputRedirected);

        // Format message without exception to avoid stack trace
        var message = logEntry.Formatter(logEntry.State, null);
        if (logEntry.Exception is not null)
            message += ": " + logEntry.Exception.Message;

        var levelLabel = GetLevelLabel(logEntry.LogLevel);

        if (_options.TimestampFormat is not null)
        {
            var ts = _options.UseUtcTimestamp ? DateTime.UtcNow : DateTime.Now;
            textWriter.Write(ts.ToString(_options.TimestampFormat));
        }

        if (colorEnabled)
        {
            var color = GetLevelColor(logEntry.LogLevel);
            if (color.Length > 0)
            {
                textWriter.Write(color);
                textWriter.Write(levelLabel);
                textWriter.Write("\x1b[0m");
            }
            else
            {
                textWriter.Write(levelLabel);
            }
        }
        else
        {
            textWriter.Write(levelLabel);
        }

        textWriter.Write(' ');
        textWriter.WriteLine(message);
    }
}
