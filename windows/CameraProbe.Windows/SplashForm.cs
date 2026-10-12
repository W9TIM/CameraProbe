using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace CameraProbe;

// Brief borderless window shown at launch (about 1.5s, then a short fade) -
// the Windows counterpart of SplashWindowController.swift. Purely cosmetic:
// nothing else depends on it. Follows the system light/dark app theme and
// never takes focus away from whatever the user is doing.
sealed class SplashForm : Form
{
    private const int VisibleMs = 1500;
    private const int FadeMs = 300;

    private readonly System.Windows.Forms.Timer _timer = new();
    private DateTime _fadeStart;

    public SplashForm()
    {
        bool dark = IsDarkTheme();
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = false;
        TopMost = true;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(280, 160);
        BackColor = dark ? Color.FromArgb(32, 32, 32) : Color.White;
        ForeColor = dark ? Color.White : Color.Black;
        Font = SystemFonts.MessageBoxFont ?? Font;

        var icon = new PictureBox
        {
            Image = TrayIcons.AppArtwork(),
            SizeMode = PictureBoxSizeMode.Zoom,
            Dock = DockStyle.Top,
            Height = 96,
            Padding = new Padding(0, 16, 0, 0),
        };
        var title = new Label
        {
            Text = $"{AppInfo.Name} {AppInfo.Version}",
            Font = new Font(Font.FontFamily, 12f, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter,
            Dock = DockStyle.Top,
            Height = 28,
        };
        var subtitle = new Label
        {
            Text = "Starting up...",
            ForeColor = dark ? Color.FromArgb(170, 170, 170) : Color.FromArgb(96, 96, 96),
            TextAlign = ContentAlignment.MiddleCenter,
            Dock = DockStyle.Top,
            Height = 22,
        };

        // Dock=Top stacks in reverse add order.
        Controls.Add(subtitle);
        Controls.Add(title);
        Controls.Add(icon);

        _timer.Interval = VisibleMs;
        _timer.Tick += OnTick;
    }

    protected override bool ShowWithoutActivation => true;

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        // Windows 11 rounded corners + shadow for a borderless window.
        int round = DWMWCP_ROUND;
        DwmSetWindowAttribute(Handle, DWMWA_WINDOW_CORNER_PREFERENCE, ref round, sizeof(int));
        _timer.Start();
    }

    private void OnTick(object? sender, EventArgs e)
    {
        if (_fadeStart == default)
        {
            _fadeStart = DateTime.Now;
            _timer.Interval = 15;
            return;
        }

        double t = (DateTime.Now - _fadeStart).TotalMilliseconds / FadeMs;
        if (t >= 1)
        {
            _timer.Stop();
            Close();
            return;
        }
        Opacity = 1 - t;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _timer.Dispose();
        base.Dispose(disposing);
    }

    private static bool IsDarkTheme()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
    }

    private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    private const int DWMWCP_ROUND = 2;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
