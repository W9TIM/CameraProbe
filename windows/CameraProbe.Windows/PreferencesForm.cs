namespace CameraProbe;

// Preferences window - the Windows counterpart of
// SettingsWindowController.swift. Edits relay enabled/host/port, Home
// Assistant enabled/host/port, the ignoredApplications list and Start at
// Login. Save writes through ConfigStore, which persists to disk and
// updates the live config immediately - no restart required.
//
// Built in code with auto-sizing table layouts (no designer file) so it
// scales cleanly at any DPI.
sealed class PreferencesForm : Form
{
    private readonly CheckBox _relayEnabled = new() { Text = "Enable relay", AutoSize = true };
    private readonly TextBox _relayHost = new() { Width = 280 };
    private readonly TextBox _relayPort = new() { Width = 80 };

    private readonly CheckBox _haEnabled = new() { Text = "Enable Home Assistant", AutoSize = true };
    private readonly TextBox _haHost = new() { Width = 280 };
    private readonly TextBox _haPort = new() { Width = 80 };

    private readonly TextBox _ignoredApps = new()
    {
        Multiline = true,
        AcceptsReturn = true,
        ScrollBars = ScrollBars.Vertical,
        Width = 380,
        Height = 100,
    };

    private readonly CheckBox _startAtLogin = new() { Text = "Start CameraProbe when I sign in", AutoSize = true };
    private readonly Label _loginNote = new() { AutoSize = true, ForeColor = SystemColors.GrayText, MaximumSize = new Size(380, 0) };
    private readonly Label _status = new() { AutoSize = true, ForeColor = Color.Firebrick, MaximumSize = new Size(380, 0) };

    public PreferencesForm()
    {
        Text = $"{AppInfo.Name} Preferences";
        Icon = TrayIcons.AppIcon(SystemInformation.IconSize);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Font = SystemFonts.MessageBoxFont ?? Font;
        Padding = new Padding(16);

        var root = new TableLayoutPanel { ColumnCount = 1, AutoSize = true, Dock = DockStyle.Fill };

        root.Controls.Add(Section("Relay"));
        root.Controls.Add(_relayEnabled);
        root.Controls.Add(HostPortRow(_relayHost, _relayPort));

        root.Controls.Add(Section("Home Assistant"));
        root.Controls.Add(_haEnabled);
        root.Controls.Add(HostPortRow(_haHost, _haPort));

        root.Controls.Add(Section("Ignored applications (one per line)"));
        root.Controls.Add(new Label
        {
            Text = "Matches the app's name or exe, e.g. \"Zoom Meetings\", \"Zoom\" or \"Zoom.exe\". Names are shown in the log.",
            AutoSize = true,
            MaximumSize = new Size(380, 0),
            ForeColor = SystemColors.GrayText,
        });
        root.Controls.Add(_ignoredApps);

        root.Controls.Add(Section("General"));
        root.Controls.Add(_startAtLogin);
        root.Controls.Add(_loginNote);

        root.Controls.Add(_status);

        var save = new Button { Text = "Save", AutoSize = true, MinimumSize = new Size(80, 0) };
        var cancel = new Button { Text = "Cancel", AutoSize = true, MinimumSize = new Size(80, 0), DialogResult = DialogResult.Cancel };
        save.Click += (_, _) => SaveClicked();
        var buttons = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 12, 0, 0),
        };
        buttons.Controls.Add(cancel);
        buttons.Controls.Add(save);
        root.Controls.Add(buttons);

        AcceptButton = save;
        CancelButton = cancel;
        Controls.Add(root);

        // Keep host/port fields greyed out while their integration is off.
        _relayEnabled.CheckedChanged += (_, _) => UpdateEnabledStates();
        _haEnabled.CheckedChanged += (_, _) => UpdateEnabledStates();

        PopulateFromCurrentConfig();
    }

    private static Label Section(string title) => new()
    {
        Text = title,
        AutoSize = true,
        Font = new Font(SystemFonts.MessageBoxFont ?? DefaultFont, FontStyle.Bold),
        Margin = new Padding(0, 12, 0, 4),
    };

    private static TableLayoutPanel HostPortRow(TextBox host, TextBox port)
    {
        var row = new TableLayoutPanel { ColumnCount = 4, AutoSize = true, Margin = new Padding(16, 0, 0, 0) };
        row.Controls.Add(new Label { Text = "Host", AutoSize = true, Anchor = AnchorStyles.Left });
        row.Controls.Add(host);
        row.Controls.Add(new Label { Text = "Port", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(12, 3, 3, 3) });
        row.Controls.Add(port);
        return row;
    }

    private void UpdateEnabledStates()
    {
        _relayHost.Enabled = _relayPort.Enabled = _relayEnabled.Checked;
        _haHost.Enabled = _haPort.Enabled = _haEnabled.Checked;
    }

    private void PopulateFromCurrentConfig()
    {
        var config = ConfigStore.Shared.Config;

        _relayEnabled.Checked = config.Relay.Enabled;
        _relayHost.Text = config.Relay.Host;
        _relayPort.Text = config.Relay.Port.ToString();

        _haEnabled.Checked = config.HomeAssistant.Enabled;
        _haHost.Text = config.HomeAssistant.Host;
        _haPort.Text = config.HomeAssistant.Port.ToString();

        _ignoredApps.Text = string.Join(Environment.NewLine, config.IgnoredApplications);

        _startAtLogin.Checked = LoginItem.IsEnabled;
        if (LoginItem.IsEnabled && !LoginItem.PointsAtThisExe)
            _loginNote.Text = $"Currently starts {LoginItem.RegisteredCommand}. Saving with this ticked switches it to this copy.";

        UpdateEnabledStates();
    }

    private void SaveClicked()
    {
        if (!TryParsePort(_relayPort.Text, out int relayPort))
        {
            Fail("Relay port must be a number between 1 and 65535.", _relayPort);
            return;
        }
        if (!TryParsePort(_haPort.Text, out int haPort))
        {
            Fail("Home Assistant port must be a number between 1 and 65535.", _haPort);
            return;
        }

        string relayHost = _relayHost.Text.Trim();
        string haHost = _haHost.Text.Trim();
        if (relayHost.Length == 0)
        {
            Fail("Relay host can't be empty.", _relayHost);
            return;
        }
        if (haHost.Length == 0)
        {
            Fail("Home Assistant host can't be empty.", _haHost);
            return;
        }

        var newConfig = new AppConfig
        {
            Relay = new RelayConfig { Enabled = _relayEnabled.Checked, Host = relayHost, Port = relayPort },
            HomeAssistant = new HomeAssistantConfig { Enabled = _haEnabled.Checked, Host = haHost, Port = haPort },
            IgnoredApplications = _ignoredApps.Lines
                .Select(line => line.Trim())
                .Where(line => line.Length > 0)
                .ToList(),
        };

        try
        {
            ConfigStore.Shared.Save(newConfig);
        }
        catch (Exception ex)
        {
            Log.Error($"Failed to save configuration: {ex.Message}");
            Fail($"Failed to save: {ex.Message}", null);
            return;
        }

        if (_startAtLogin.Checked != LoginItem.IsEnabled || (_startAtLogin.Checked && !LoginItem.PointsAtThisExe))
        {
            if (!LoginItem.SetEnabled(_startAtLogin.Checked))
            {
                Fail("Settings saved, but Start at Login couldn't be updated. See the log for details.", null);
                return;
            }
        }

        Close();
    }

    private static bool TryParsePort(string text, out int port) =>
        int.TryParse(text.Trim(), out port) && port is >= 1 and <= 65535;

    private void Fail(string message, Control? focus)
    {
        _status.Text = message;
        focus?.Focus();
    }
}
