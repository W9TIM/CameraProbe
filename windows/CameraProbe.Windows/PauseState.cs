namespace CameraProbe;

// Backs the "Inactivate" tray menu item. While paused, camera detection
// keeps running (session tracking stays consistent) but relay/Home
// Assistant notifications are suppressed for any session that starts -
// same idea as ignoredApplications, just a manual global switch.
static class PauseState
{
    private static readonly object Lock = new();
    private static bool _isPaused;

    public static event Action<bool>? Changed;

    public static bool IsPaused
    {
        get { lock (Lock) return _isPaused; }
    }

    public static bool Toggle()
    {
        bool value;
        lock (Lock) value = _isPaused = !_isPaused;
        Log.Info(value ? "Notifications inactivated from tray menu" : "Notifications reactivated from tray menu");
        Changed?.Invoke(value);
        return value;
    }
}
