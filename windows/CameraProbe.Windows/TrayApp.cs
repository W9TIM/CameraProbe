using System.Net;
using Microsoft.Win32;

namespace CameraProbe;

// Tray icon and menu - the Windows counterpart of StatusBarController.swift.
//
// The red dot reflects ONLY CameraProbe's own local detection: it is on
// exactly when the camera is in use by a non-excluded app AND Inactivate is
// off. It is deliberately independent of the relay and Home Assistant (not
// gated on whether they are enabled, configured or reachable), updates
// instantly from CameraMonitor's events (no relay polling), and goes dark
// immediately when Inactivate is turned on.
sealed class TrayApp : ApplicationContext
{
    private readonly TrayIcons _icons = new();
    private readonly NotifyIcon _notifyIcon;
    private readonly ToolStripMenuItem _pauseItem;
    private readonly CameraMonitor _monitor = new();
    private readonly SynchronizationContext _ui;

    public TrayApp()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add($"About {AppInfo.Name}", null, (_, _) => ShowAbout());
        menu.Items.Add("Preferences...", null, (_, _) => ShowPreferences());
        menu.Items.Add(new ToolStripSeparator());
        _pauseItem = new ToolStripMenuItem("Inactivate", null, (_, _) => PauseState.Toggle());
        menu.Items.Add(_pauseItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Quit());

        // Creating the menu (a Control) installs the WinForms sync context.
        _ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();

        _notifyIcon = new NotifyIcon
        {
            Icon = _icons.Plain,
            Text = AppInfo.Name,
            ContextMenuStrip = menu,
            Visible = true,
        };
        _notifyIcon.DoubleClick += (_, _) => ShowPreferences();

        new SplashForm().Show();

        _monitor.ActivityChanged += _ => _ui.Post(_ => UpdateIndicator(), null);
        PauseState.Changed += _ => _ui.Post(_ => UpdateIndicator(), null);

        // Sign-out/shutdown/restart: send "off" if needed before Windows
        // ends the process.
        SystemEvents.SessionEnding += OnSessionEnding;

        LogStartupBanner();
        _monitor.Start();
        UpdateIndicator();
    }

    private void UpdateIndicator()
    {
        bool paused = PauseState.IsPaused;
        bool inUse = _monitor.IsActive;
        bool dot = inUse && !paused;

        _notifyIcon.Icon = dot ? _icons.WithDot : _icons.Plain;
        _notifyIcon.Text = paused ? $"{AppInfo.Name} (inactive)"
            : inUse ? $"{AppInfo.Name} - camera in use"
            : AppInfo.Name;
        _pauseItem.Text = paused ? "Reactivate" : "Inactivate";
    }

    private PreferencesForm? _preferences;

    private void ShowPreferences()
    {
        if (_preferences is null || _preferences.IsDisposed)
        {
            _preferences = new PreferencesForm();
            _preferences.FormClosed += (_, _) => _preferences = null;
            _preferences.Show();
        }
        _preferences.Activate();
    }

    private AboutForm? _about;

    private void ShowAbout()
    {
        if (_about is null || _about.IsDisposed)
        {
            _about = new AboutForm();
            _about.FormClosed += (_, _) => _about = null;
            _about.Show();
        }
        _about.Activate();
    }

    private void Quit()
    {
        Log.Info("Quit from tray menu");
        _notifyIcon.Visible = false;
        _monitor.Shutdown();
        ExitThread();
    }

    private void OnSessionEnding(object? sender, SessionEndingEventArgs e)
    {
        Log.Info($"Windows session ending ({e.Reason})");
        _monitor.Shutdown();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            SystemEvents.SessionEnding -= OnSessionEnding;
            _monitor.Shutdown();
            _notifyIcon.Dispose();
            _icons.Dispose();
        }
        base.Dispose(disposing);
    }

    private static void LogStartupBanner()
    {
        var config = ConfigStore.Shared.Config;
        Log.Info($"{AppInfo.Name} {AppInfo.Version} starting - " +
            $"relay {config.Relay.Host}:{config.Relay.Port} (enabled: {config.Relay.Enabled}), " +
            $"Home Assistant {config.HomeAssistant.Host}:{config.HomeAssistant.Port} (enabled: {config.HomeAssistant.Enabled}), " +
            $"ignored: [{string.Join(", ", config.IgnoredApplications)}]");

        // Resolve both hosts in the background so a slow mDNS lookup never
        // delays startup; results only go to the log.
        foreach (string host in new[] { config.Relay.Host, config.HomeAssistant.Host })
        {
            Task.Run(async () =>
            {
                try
                {
                    var addresses = await Dns.GetHostAddressesAsync(host);
                    Log.Info($"DNS OK: {host} -> {string.Join(", ", addresses.Select(a => a.ToString()))}");
                }
                catch (Exception ex)
                {
                    Log.Error($"DNS FAILED: {host} ({ex.Message})");
                }
            });
        }
    }
}
