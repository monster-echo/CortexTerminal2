using Serilog.Core;
using Serilog.Events;

#if IOS || ANDROID
using Plugin.Firebase.Crashlytics;
#endif

namespace CortexTerminal.Mobile.App.Services;

public class FirebaseCrashlyticsSink : ILogEventSink
{
    private readonly IFormatProvider _formatProvider;

    public FirebaseCrashlyticsSink(IFormatProvider formatProvider)
    {
        _formatProvider = formatProvider;
    }

    public void Emit(LogEvent logEvent)
    {
        try
        {
            var message = logEvent.RenderMessage(_formatProvider);
            var finalMessage = $"[{logEvent.Level}] {message}";

#if IOS || ANDROID
            CrossFirebaseCrashlytics.Current.Log(finalMessage);

            if (logEvent.Exception != null)
            {
                CrossFirebaseCrashlytics.Current.RecordException(logEvent.Exception);
            }
#endif
        }
        catch
        {
        }
    }
}
