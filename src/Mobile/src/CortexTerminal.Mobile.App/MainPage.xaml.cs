using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using CommunityToolkit.Maui.Core;
using CortexTerminal.Mobile.App.Services.Bridge;
using Microsoft.Extensions.Logging;
using Microsoft.Maui.Dispatching;

namespace CortexTerminal.Mobile.App;

public partial class MainPage : ContentPage
{
	private readonly AppBridge _bridge;
	private readonly ILogger<MainPage> _logger;
	private CancellationTokenSource? _splashTimeoutCts;

	public static readonly BindableProperty NativeStatusBarColorProperty =
		BindableProperty.Create(nameof(NativeStatusBarColor), typeof(Color), typeof(MainPage), Color.FromArgb("#121212"));

	public static readonly BindableProperty NativeStatusBarStyleProperty =
		BindableProperty.Create(nameof(NativeStatusBarStyle), typeof(StatusBarStyle), typeof(MainPage), StatusBarStyle.LightContent);

	public static readonly BindableProperty IsLoadingProperty =
		BindableProperty.Create(nameof(IsLoading), typeof(bool), typeof(MainPage), true);

	public Color NativeStatusBarColor
	{
		get => (Color)GetValue(NativeStatusBarColorProperty);
		set => SetValue(NativeStatusBarColorProperty, value);
	}

	public StatusBarStyle NativeStatusBarStyle
	{
		get => (StatusBarStyle)GetValue(NativeStatusBarStyleProperty);
		set => SetValue(NativeStatusBarStyleProperty, value);
	}

	public bool IsLoading
	{
		get => (bool)GetValue(IsLoadingProperty);
		set => SetValue(IsLoadingProperty, value);
	}

	public MainPage(AppBridge bridge, ILogger<MainPage> logger)
	{
		InitializeComponent();
		_bridge = bridge;
		_logger = logger;

		// Set initial status bar values BEFORE BindingContext so StatusBarBehavior
		// picks up the correct values immediately (matching v2ex.maui2 pattern).
		if (Application.Current?.RequestedTheme == AppTheme.Dark)
		{
			NativeStatusBarColor = Color.FromArgb("#121212");
			NativeStatusBarStyle = StatusBarStyle.LightContent;
			BackgroundColor = Color.FromArgb("#121212");
		}
		else
		{
			NativeStatusBarColor = Color.FromArgb("#f4f4f5");
			NativeStatusBarStyle = StatusBarStyle.DarkContent;
			BackgroundColor = Color.FromArgb("#ffffff");
		}

		BindingContext = this;

		hybridWebView.SetInvokeJavaScriptTarget(_bridge);
		_bridge.ConfigureWebViewMessaging(SendRawMessageToWebViewAsync);

		if (Application.Current is not null)
		{
			Application.Current.RequestedThemeChanged += (_, args) =>
			{
				ApplyNativeTheme(args.RequestedTheme == AppTheme.Dark ? "dark" : "light");
			};
		}

		App.AppResumed += OnAppResumed;
		ShowSplashScreenWithTimeout(TimeSpan.FromSeconds(5));
	}

	protected override void OnAppearing()
	{
		base.OnAppearing();
		// Re-apply theme to ensure native status bar icons are correct
		// (Platform.CurrentActivity may not be ready during construction)
		ApplyNativeTheme(Application.Current?.RequestedTheme == AppTheme.Dark ? "dark" : "light");
		App.AppResumed -= OnAppResumed;
		App.AppResumed += OnAppResumed;
	}

	protected override void OnDisappearing()
	{
		base.OnDisappearing();
		App.AppResumed -= OnAppResumed;
	}

	private void ShowSplashScreenWithTimeout(TimeSpan timeout)
	{
		IsLoading = true;
		splashScreen.IsVisible = true;
		splashScreen.Opacity = 1;

		_splashTimeoutCts?.Cancel();
		_splashTimeoutCts = new CancellationTokenSource();
		var token = _splashTimeoutCts.Token;

		Task.Run(async () =>
		{
			try
			{
				await Task.Delay(timeout, token);
				MainThread.BeginInvokeOnMainThread(() =>
				{
					if (IsLoading)
					{
						_logger.LogWarning("Splash timeout reached, hiding overlay.");
						HideSplashScreen();
					}
				});
			}
			catch (TaskCanceledException)
			{
			}
		}, token);
	}

	private async void HideSplashScreen()
	{
		try
		{
			await splashScreen.FadeToAsync(0, 250, Easing.Linear);
		}
		catch (Exception ex)
		{
			_logger.LogDebug(ex, "Failed to animate splash screen fade out.");
		}

		splashScreen.IsVisible = false;
		IsLoading = false;
	}

	private void OnAppResumed()
	{
		Task.Run(async () =>
		{
			await Task.Delay(300);
			MainThread.BeginInvokeOnMainThread(async () =>
			{
				try
				{
					await HandleResumeAsync();
				}
				catch (Exception ex)
				{
					_logger.LogError(ex, "Resume handling failed.");
					HideSplashScreen();
				}
			});
		});
	}

	private async Task HandleResumeAsync()
	{
		if (hybridWebView?.Handler?.PlatformView is null)
		{
			return;
		}

		if (!IsWebViewAttached(hybridWebView.Handler.PlatformView))
		{
			return;
		}

		// 1. 静默探活：给 WebView 300 毫秒的时间来回应心跳
		// 如果应用只是短暂切出并秒回，且前端运行正常，我们就完全跳过动画遮罩，避免白屏闪烁
		var healthTask = CheckWebViewHealthAsync();
		var firstCompleted = await Task.WhenAny(healthTask, Task.Delay(300));

		if (firstCompleted == healthTask && await healthTask)
		{
			DispatchPendingNavigation();
			return;
		}

		// 2. 超时未回应，或者判定假死：这时候必须拉起加载遮罩蒙层了
		ShowSplashScreenWithTimeout(TimeSpan.FromSeconds(8));

		// 3. 再给它最多 2 秒的时间挣扎一下，确认是不是彻底卡死了
		if (!healthTask.IsCompleted)
		{
			firstCompleted = await Task.WhenAny(healthTask, Task.Delay(2000));
		}

		if (firstCompleted != healthTask || !(await healthTask))
		{
			// 确认无法抢救，执行重新加载操作
			await RecoverWebViewAsync();
			return;
		}

		HideSplashScreen();
		DispatchPendingNavigation();
	}

	private bool IsWebViewAttached(object platformView)
	{
		try
		{
#if ANDROID
			if (platformView is Android.Webkit.WebView androidWebView)
			{
				return androidWebView.Handle != IntPtr.Zero
					&& androidWebView.Context is not null
					&& androidWebView.IsAttachedToWindow
					&& androidWebView.WindowVisibility == Android.Views.ViewStates.Visible;
			}
#endif
#if IOS || MACCATALYST
			if (platformView is WebKit.WKWebView wkWebView)
			{
				return wkWebView.Window is not null && wkWebView.Superview is not null;
			}
#endif
			return true;
		}
		catch
		{
			return false;
		}
	}

	private async Task<bool> CheckWebViewHealthAsync()
	{
		try
		{
			var result = await hybridWebView.InvokeJavaScriptAsync("checkWebViewHealth", HybridJsonContext.Default.String);
			return result is "\"HEALTHY\"" or "HEALTHY";
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "WebView health check failed.");
			return false;
		}
	}

	private async Task RecoverWebViewAsync()
	{
		var platformView = hybridWebView?.Handler?.PlatformView;

#if ANDROID
		if (platformView is Android.Webkit.WebView androidWebView)
		{
			androidWebView.StopLoading();
			await Task.Delay(50);
			androidWebView.Reload();
			return;
		}
#endif

#if IOS || MACCATALYST
		if (platformView is WebKit.WKWebView wkWebView)
		{
			wkWebView.Reload();
			return;
		}
#endif

		HideSplashScreen();
	}

	private void OnHybridWebViewLoaded(object? sender, EventArgs e)
	{
		_logger.LogInformation("HybridWebView loaded.");
	}

	private void OnHybridWebViewWebResourceRequested(object? sender, WebViewWebResourceRequestedEventArgs e)
	{
		try
		{
			if (!string.Equals(e.Method, "GET", StringComparison.OrdinalIgnoreCase)
				&& !string.Equals(e.Method, "HEAD", StringComparison.OrdinalIgnoreCase))
			{
				return;
			}

			if (!_bridge.TryResolveWebFile(e.Uri, out var file) || file is null)
			{
				return;
			}

			if (!File.Exists(file.FilePath))
			{
				e.Handled = true;
				e.SetResponse(404, "Not Found");
				return;
			}

			var fileInfo = new FileInfo(file.FilePath);
			var headers = new Dictionary<string, string>
			{
				["Cache-Control"] = "no-cache",
				["Accept-Ranges"] = "bytes",
				["Content-Type"] = file.ContentType,
			};

			if (TryCreateRangeResponse(e, file.FilePath, fileInfo.Length, headers))
			{
				return;
			}

			headers["Content-Length"] = fileInfo.Length.ToString();
			e.Handled = true;
			e.SetResponse(200, "OK", headers, OpenFileAsync(file.FilePath, 0, null));
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "Failed to handle WebResourceRequested for {Uri}.", e.Uri);
		}
	}

	private void OnHybridWebViewRawMessageReceived(object? sender, HybridWebViewRawMessageReceivedEventArgs e)
	{
		if (string.IsNullOrWhiteSpace(e.Message))
		{
			return;
		}

		try
		{
			using var document = JsonDocument.Parse(e.Message);
			var root = document.RootElement;
			if (!root.TryGetProperty("type", out var typeProp))
			{
				return;
			}

			switch (typeProp.GetString())
			{
				case "appInit":
					HandleAppInit();
					break;
				case "appReady":
					HandleAppReady();
					break;
				case "bridgeDemo.text":
					HandleBridgeDemoText(root);
					break;
				case "bridgeDemo.binary":
					HandleBridgeDemoBinary(root);
					break;
				case "bridgeStream.start":
					HandleBridgeStreamStart(root);
					break;
				case "bridgeStream.stop":
					HandleBridgeStreamStop();
					break;
				case "theme":
					var mode = root.TryGetProperty("mode", out var modeProp) ? modeProp.GetString() : null;
					if (mode is "light" or "dark")
					{
						ApplyNativeTheme(mode);
					}
					break;
			}
		}
		catch (Exception ex)
		{
			_logger.LogDebug(ex, "Failed to parse raw message from HybridWebView.");
		}
	}

	private void HandleBridgeStreamStart(JsonElement root)
	{
		var chunkByteLength = GetIntProperty(root, "chunkByteLength", 256);
		var chunkCount = GetIntProperty(root, "chunkCount", 20);
		var intervalMs = GetIntProperty(root, "intervalMs", 250);

		_ = _bridge.StartBinaryStreamToJsAsync(chunkByteLength, chunkCount, intervalMs);
	}

	private void HandleBridgeStreamStop()
	{
		_ = _bridge.StopBinaryStreamToJsAsync();
	}

	private void HandleAppInit()
	{
		var payload = new
		{
			type = "initData",
			payload = new
			{
				platform = DeviceInfo.Platform.ToString() switch
				{
					"Android" => "android",
					"iOS" => "ios",
					"MacCatalyst" => "maccatalyst",
					"WinUI" => "windows",
					_ => "unknown",
				},
				appName = AppInfo.Current.Name,
			}
		};

		SendRawMessageToWebView(JsonSerializer.Serialize(payload), "app init payload");
	}

	private void HandleBridgeDemoText(JsonElement root)
	{
		var text = root.TryGetProperty("text", out var textProp)
			? textProp.GetString() ?? string.Empty
			: string.Empty;

		SendRawMessageToWebView(JsonSerializer.Serialize(new
		{
			type = "bridgeDemo.response",
			direction = "js-to-csharp-text",
			source = "csharp",
			text = $"C# 已收到文本：{text}",
			length = text.Length,
			receivedAt = DateTimeOffset.UtcNow,
		}), "bridge text response");
	}

	private void HandleBridgeDemoBinary(JsonElement root)
	{
		var base64 = root.TryGetProperty("base64", out var base64Prop)
			? base64Prop.GetString() ?? string.Empty
			: string.Empty;

		var bytes = string.IsNullOrWhiteSpace(base64)
			? Array.Empty<byte>()
			: Convert.FromBase64String(base64);
		var checksum = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

		SendRawMessageToWebView(JsonSerializer.Serialize(new
		{
			type = "bridgeDemo.response",
			direction = "js-to-csharp-binary",
			source = "csharp",
			byteLength = bytes.Length,
			checksum,
			base64 = Convert.ToBase64String(bytes),
			receivedAt = DateTimeOffset.UtcNow,
		}), "bridge binary response");
	}

	private void HandleAppReady()
	{
		_splashTimeoutCts?.Cancel();
		_splashTimeoutCts = null;
		MainThread.BeginInvokeOnMainThread(HideSplashScreen);
	}

	private void DispatchPendingNavigation()
	{
		try
		{
			var route = Preferences.Get(AppBridge.PendingNavigationRouteKey, string.Empty);
			if (string.IsNullOrWhiteSpace(route))
			{
				return;
			}

			var payload = Preferences.Get(AppBridge.PendingNavigationPayloadKey, string.Empty);
			SendRawMessageToWebView(JsonSerializer.Serialize(new
			{
				type = "pushNavigate",
				route,
				payload,
			}), "pending navigation");

			Preferences.Remove(AppBridge.PendingNavigationRouteKey);
			Preferences.Remove(AppBridge.PendingNavigationPayloadKey);
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "Failed to dispatch pending navigation.");
		}
	}

	private void SendRawMessageToWebView(string message, string reason)
	{
		_ = SendRawMessageToWebViewAsync(message, reason);
	}

	private Task SendRawMessageToWebViewAsync(string message, string reason)
	{
		var completion = new TaskCompletionSource<object?>();

		MainThread.BeginInvokeOnMainThread(() =>
		{
			try
			{
				hybridWebView.SendRawMessage(message);
				completion.TrySetResult(null);
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Failed to send {Reason} to HybridWebView.", reason);
				completion.TrySetException(ex);
			}
		});

		return completion.Task;
	}

	private static bool TryCreateRangeResponse(
		WebViewWebResourceRequestedEventArgs e,
		string filePath,
		long totalLength,
		Dictionary<string, string> headers)
	{
		if (!e.Headers.TryGetValue("Range", out var rangeHeader) || string.IsNullOrWhiteSpace(rangeHeader))
		{
			return false;
		}

		if (!TryParseByteRange(rangeHeader, totalLength, out var start, out var end))
		{
			e.Handled = true;
			e.SetResponse(416, "Range Not Satisfiable");
			return true;
		}

		var rangeLength = end - start + 1;
		headers["Content-Length"] = rangeLength.ToString();
		headers["Content-Range"] = $"bytes {start}-{end}/{totalLength}";
		e.Handled = true;
		e.SetResponse(206, "Partial Content", headers, OpenFileAsync(filePath, start, rangeLength));
		return true;
	}

	private static bool TryParseByteRange(string rangeHeader, long totalLength, out long start, out long end)
	{
		start = 0;
		end = totalLength - 1;

		if (!rangeHeader.StartsWith("bytes=", StringComparison.OrdinalIgnoreCase))
		{
			return false;
		}

		var value = rangeHeader[6..];
		var separatorIndex = value.IndexOf('-');
		if (separatorIndex < 0)
		{
			return false;
		}

		var startPart = value[..separatorIndex].Trim();
		var endPart = value[(separatorIndex + 1)..].Trim();

		if (string.IsNullOrEmpty(startPart))
		{
			if (!long.TryParse(endPart, out var suffixLength) || suffixLength <= 0)
			{
				return false;
			}

			start = Math.Max(totalLength - suffixLength, 0);
			end = totalLength - 1;
			return true;
		}

		if (!long.TryParse(startPart, out start) || start < 0 || start >= totalLength)
		{
			return false;
		}

		if (string.IsNullOrEmpty(endPart))
		{
			end = totalLength - 1;
			return true;
		}

		if (!long.TryParse(endPart, out end) || end < start)
		{
			return false;
		}

		end = Math.Min(end, totalLength - 1);
		return true;
	}

	private static Task<Stream?> OpenFileAsync(string filePath, long offset, long? length)
	{
		Stream stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
		if (offset > 0)
		{
			stream.Seek(offset, SeekOrigin.Begin);
		}

		if (length is not null)
		{
			stream = new SegmentReadStream(stream, length.Value);
		}

		return Task.FromResult<Stream?>(stream);
	}

	private static int GetIntProperty(JsonElement root, string propertyName, int defaultValue)
	{
		if (!root.TryGetProperty(propertyName, out var property))
		{
			return defaultValue;
		}

		return property.ValueKind switch
		{
			JsonValueKind.Number when property.TryGetInt32(out var numberValue) => numberValue,
			JsonValueKind.String when int.TryParse(property.GetString(), out var stringValue) => stringValue,
			_ => defaultValue,
		};
	}

	private void ApplyNativeTheme(string mode)
	{
		MainThread.BeginInvokeOnMainThread(() =>
		{
			var isDark = mode == "dark";
			NativeStatusBarColor = Color.FromArgb(isDark ? "#121212" : "#f4f4f5");
			NativeStatusBarStyle = isDark ? StatusBarStyle.LightContent : StatusBarStyle.DarkContent;
			BackgroundColor = Color.FromArgb(isDark ? "#121212" : "#ffffff");
			splashScreen.BackgroundColor = Color.FromArgb(isDark ? "#121212" : "#ffffff");

#if ANDROID
			if (Platform.CurrentActivity?.Window is not null)
			{
				var window = Platform.CurrentActivity.Window;
#pragma warning disable CA1422
				if (Android.OS.Build.VERSION.SdkInt >= (Android.OS.BuildVersionCodes)35)
				{
					window.SetStatusBarColor(Android.Graphics.Color.Transparent);
					window.SetNavigationBarColor(Android.Graphics.Color.Transparent);
				}
				else
				{
					var statusColor = Android.Graphics.Color.ParseColor(isDark ? "#121212" : "#f4f4f5");
					var navigationColor = Android.Graphics.Color.ParseColor(isDark ? "#121212" : "#ffffff");
					window.SetStatusBarColor(statusColor);
					window.SetNavigationBarColor(navigationColor);
				}
#pragma warning restore CA1422

				var controller = AndroidX.Core.View.WindowCompat.GetInsetsController(window, window.DecorView);
				if (controller is not null)
				{
					controller.AppearanceLightStatusBars = !isDark;
					controller.AppearanceLightNavigationBars = !isDark;
				}
			}
#endif
		});
	}

#if ANDROID
	protected override bool OnBackButtonPressed()
	{
		try
		{
			MainThread.BeginInvokeOnMainThread(() =>
			{
				try
				{
					var androidWebView = hybridWebView.Handler?.PlatformView as Android.Webkit.WebView;
					if (androidWebView is not null && androidWebView.CanGoBack())
					{
						androidWebView.GoBack();
					}
				}
				catch (Exception ex)
				{
					_logger.LogError(ex, "Failed to delegate back navigation to WebView.");
					base.OnBackButtonPressed();
				}
			});
			return true;
		}
		catch (Exception ex)
		{
			_logger.LogError(ex, "Back button handling crashed.");
			return base.OnBackButtonPressed();
		}
	}
#endif


	[JsonSourceGenerationOptions(WriteIndented = false)]
	[JsonSerializable(typeof(string))]
	internal partial class HybridJsonContext : JsonSerializerContext
	{
	}

	private sealed class SegmentReadStream(Stream innerStream, long remainingBytes) : Stream
	{
		private readonly Stream _innerStream = innerStream;
		private long _remainingBytes = remainingBytes;

		public override bool CanRead => _innerStream.CanRead;
		public override bool CanSeek => false;
		public override bool CanWrite => false;
		public override long Length => _remainingBytes;
		public override long Position
		{
			get => throw new NotSupportedException();
			set => throw new NotSupportedException();
		}

		public override void Flush()
		{
		}

		public override int Read(byte[] buffer, int offset, int count)
		{
			if (_remainingBytes <= 0)
			{
				return 0;
			}

			var bytesToRead = (int)Math.Min(count, _remainingBytes);
			var read = _innerStream.Read(buffer, offset, bytesToRead);
			_remainingBytes -= read;
			return read;
		}

		public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
		{
			if (_remainingBytes <= 0)
			{
				return 0;
			}

			var bytesToRead = (int)Math.Min(buffer.Length, _remainingBytes);
			var read = await _innerStream.ReadAsync(buffer[..bytesToRead], cancellationToken);
			_remainingBytes -= read;
			return read;
		}

		protected override void Dispose(bool disposing)
		{
			if (disposing)
			{
				_innerStream.Dispose();
			}

			base.Dispose(disposing);
		}

		public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
		public override void SetLength(long value) => throw new NotSupportedException();
		public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
	}
}
