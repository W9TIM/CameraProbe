using System.Text;

namespace CameraProbe;

// The relay (GET /on, /off) and Home Assistant webhook (POST
// /api/webhook/camera_on|camera_off) calls. Fire-and-forget like the macOS
// version, but each integration's requests are chained so an "off" can
// never overtake the "on" that preceded it.
static class Notifier
{
    public static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(5) };

    private static readonly object Lock = new();
    private static Task _relayChain = Task.CompletedTask;
    private static Task _homeAssistantChain = Task.CompletedTask;

    /// Returns a task that completes once this request (and every earlier
    /// one) has finished - only awaited when quitting, see CameraMonitor.Shutdown.
    public static Task SendRelayCommand(string command)
    {
        var relay = ConfigStore.Shared.Config.Relay;
        if (!relay.Enabled) return Task.CompletedTask;

        string url = $"http://{relay.Host}:{relay.Port}/{command}";
        return Enqueue(ref _relayChain, async () =>
        {
            Log.Info($"Sending relay {command} -> {url}");
            try
            {
                using var response = await Http.GetAsync(url);
                string reply = await response.Content.ReadAsStringAsync();
                Log.Info($"Relay HTTP {(int)response.StatusCode}: {reply.Trim()}");
            }
            catch (Exception ex)
            {
                Log.Error($"Relay HTTP error: {ex.Message}");
            }
        });
    }

    public static Task SendHomeAssistantEvent(string eventName, string application = "")
    {
        var homeAssistant = ConfigStore.Shared.Config.HomeAssistant;
        if (!homeAssistant.Enabled) return Task.CompletedTask;

        string url = $"http://{homeAssistant.Host}:{homeAssistant.Port}/api/webhook/{eventName}";
        return Enqueue(ref _homeAssistantChain, async () =>
        {
            Log.Info($"Sending Home Assistant {eventName} -> {url}");
            try
            {
                using var content = string.IsNullOrEmpty(application)
                    ? null
                    : new StringContent($"application={Uri.EscapeDataString(application)}",
                        Encoding.UTF8, "application/x-www-form-urlencoded");
                using var response = await Http.PostAsync(url, content);
                string reply = await response.Content.ReadAsStringAsync();
                Log.Info($"Home Assistant HTTP {(int)response.StatusCode}{(reply.Length > 0 ? ": " + reply.Trim() : "")}");
            }
            catch (Exception ex)
            {
                Log.Error($"Home Assistant error: {ex.Message}");
            }
        });
    }

    private static Task Enqueue(ref Task chain, Func<Task> send)
    {
        lock (Lock)
            return chain = chain.ContinueWith(_ => send(), TaskScheduler.Default).Unwrap();
    }
}
