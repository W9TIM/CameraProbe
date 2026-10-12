namespace CameraProbe;

// Camera session state machine - the Windows counterpart of CameraState /
// CameraMonitorService in CameraMonitor.swift.
//
// The sensor monitor hands us the full set of streaming PIDs on every
// change. Apps in ignoredApplications are filtered out first, so they are
// simply invisible: a session is "the camera is in use by at least one
// non-ignored app".
//
//  - Session start: "on" is sent immediately for the first app seen, unless
//    Inactivate is on, in which case nothing is sent for this session.
//    (No 3-second delay - unlike macOS we know the real app straight away.)
//  - Session end: only once the camera has stayed off for OffGrace, because
//    browsers restart the stream several times in quick succession. "off"
//    is sent only if this session's "on" was actually sent - never a lone
//    "off".
sealed class CameraMonitor : IDisposable
{
    public static readonly TimeSpan OffGrace = TimeSpan.FromSeconds(2);

    private readonly object _lock = new();
    private readonly System.Threading.Timer _offTimer;
    private SensorActivityMonitor? _sensor;
    private IReadOnlyList<int> _streamingPids = Array.Empty<int>();
    private bool _sessionActive;
    private bool _sessionNotified;
    private bool _offPending;
    private bool _shutDown;

    /// Raised (on a background thread) when IsActive changes.
    public event Action<bool>? ActivityChanged;

    public CameraMonitor()
    {
        _offTimer = new System.Threading.Timer(_ => OnOffGraceElapsed());
    }

    /// True while a session is in progress: the camera is in use by a
    /// non-ignored app (including the brief OffGrace window). Independent
    /// of Inactivate - the tray combines the two for the red dot.
    public bool IsActive
    {
        get { lock (_lock) return _sessionActive; }
    }

    public bool IsRunning => _sensor is not null;

    public void Start()
    {
        try
        {
            var sensor = new SensorActivityMonitor(OnReport);
            sensor.Start();
            _sensor = sensor;
            Log.Info("Camera sensor activity monitor started");
        }
        catch (Exception ex)
        {
            Log.Error($"Failed to start camera monitor: {ex.Message}");
        }
    }

    /// Called on Quit and at sign-out/shutdown. If this session's "on" was
    /// sent, sends the matching "off" and waits briefly for it, so the light
    /// and Home Assistant aren't left on after CameraProbe exits. Safe to
    /// call more than once.
    public void Shutdown()
    {
        var pending = new List<Task>();
        lock (_lock)
        {
            if (_shutDown) return;
            _shutDown = true;
            _offPending = false;
            _offTimer.Change(Timeout.Infinite, Timeout.Infinite);
            if (_sessionActive && _sessionNotified)
            {
                Log.Info("CAMERA OFF (CameraProbe is exiting during an active session)");
                pending.Add(Notifier.SendRelayCommand("off"));
                pending.Add(Notifier.SendHomeAssistantEvent("camera_off"));
            }
            _sessionActive = false;
            _sessionNotified = false;
        }

        // HttpClient times out at 5s; allow a little more, then give up.
        if (pending.Count > 0 && !Task.WaitAll(pending.ToArray(), TimeSpan.FromSeconds(6)))
            Log.Warn("Timed out sending \"off\" while exiting");

        Dispose();
    }

    public void Dispose()
    {
        _sensor?.Dispose();
        _sensor = null;
        _offTimer.Dispose();
    }

    private void OnReport(IReadOnlyList<int> streamingPids)
    {
        bool? changed = null;
        lock (_lock)
        {
            if (_shutDown) return;
            _streamingPids = streamingPids;
            var apps = VisibleApps();

            if (apps.Count > 0)
            {
                if (_offPending)
                {
                    _offPending = false;
                    _offTimer.Change(Timeout.Infinite, Timeout.Infinite);
                }

                if (!_sessionActive)
                {
                    _sessionActive = true;
                    changed = true;
                    StartSession(apps[0]);
                }
            }
            else if (_sessionActive && !_offPending)
            {
                _offPending = true;
                _offTimer.Change(OffGrace, Timeout.InfiniteTimeSpan);
            }
        }
        if (changed is bool active) ActivityChanged?.Invoke(active);
    }

    private void OnOffGraceElapsed()
    {
        lock (_lock)
        {
            if (_shutDown || !_offPending) return;
            _offPending = false;

            // The ignore list may have changed during the grace period, so
            // re-filter rather than trusting the last decision.
            if (VisibleApps().Count > 0) return;

            _sessionActive = false;
            EndSession();
        }
        ActivityChanged?.Invoke(false);
    }

    // Must be called with _lock held.
    private void StartSession(CameraApp app)
    {
        _sessionNotified = false;

        if (PauseState.IsPaused)
        {
            Log.Info($"CAMERA ON - {app.Name} (inactivated from tray menu, no notification sent)");
            return;
        }

        _sessionNotified = true;
        Log.Info($"CAMERA ON - {app.Name} ({app.ExeName}, pid {app.Pid})");
        Notifier.SendRelayCommand("on");
        Notifier.SendHomeAssistantEvent("camera_on", app.Name);
    }

    // Must be called with _lock held.
    private void EndSession()
    {
        if (!_sessionNotified)
        {
            Log.Info("CAMERA OFF (suppressed - matching \"on\" was never sent)");
            return;
        }

        _sessionNotified = false;
        Log.Info("CAMERA OFF");
        Notifier.SendRelayCommand("off");
        Notifier.SendHomeAssistantEvent("camera_off");
    }

    // Must be called with _lock held.
    private List<CameraApp> VisibleApps()
    {
        var apps = new List<CameraApp>();
        foreach (int pid in _streamingPids)
        {
            var app = CameraApp.Resolve(pid);
            if (app.IsIgnored)
                Log.Info($"Camera in use by {app.Name} (ignored by config)");
            else
                apps.Add(app);
        }
        return apps;
    }
}
