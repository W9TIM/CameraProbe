using System.Diagnostics;

namespace CameraProbe;

// About window - mirrors the macOS standard About panel (app icon, name,
// version, one-line description), plus short links to the project page and
// to the config and log files (shown selected in File Explorer) instead of
// spelling out long %APPDATA% paths.
sealed class AboutForm : Form
{
    private const string RepoUrl = "https://github.com/W9TIM/CameraProbe";

    public AboutForm()
    {
        Text = $"About {AppInfo.Name}";
        Icon = TrayIcons.AppIcon(SystemInformation.IconSize);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Font = SystemFonts.MessageBoxFont ?? Font;
        Padding = new Padding(20);

        var icon = new PictureBox
        {
            Image = TrayIcons.AppArtwork(),
            SizeMode = PictureBoxSizeMode.Zoom,
            Size = new Size(96, 96),
            Margin = new Padding(0, 0, 20, 0),
        };

        var name = new Label
        {
            Text = AppInfo.Name,
            AutoSize = true,
            Font = new Font(Font.FontFamily, 16f, FontStyle.Bold),
            Margin = new Padding(0, 0, 0, 2),
        };
        var version = new Label
        {
            Text = $"Version {AppInfo.Version}",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Margin = new Padding(2, 0, 0, 10),
        };
        var description = new Label
        {
            Text = "Watches for camera activity and flips a physical relay / notifies Home Assistant.",
            AutoSize = true,
            MaximumSize = new Size(420, 0),
            Margin = new Padding(2, 0, 0, 8),
        };
        var heading = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
        heading.Controls.AddRange([name, version, description]);
        heading.Controls.Add(Link("Project page", () => Open(RepoUrl)));
        heading.Controls.Add(Link($"Show {Path.GetFileName(ConfigStore.FilePath)}", () => ShowInExplorer(ConfigStore.FilePath)));
        heading.Controls.Add(Link($"Show {Path.GetFileName(Log.FilePath)}", () => ShowInExplorer(Log.FilePath)));

        var top = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, AutoSize = true, WrapContents = false };
        top.Controls.AddRange([icon, heading]);

        var ok = new Button { Text = "OK", AutoSize = true, MinimumSize = new Size(80, 0), DialogResult = DialogResult.OK };
        ok.Click += (_, _) => Close();
        var buttons = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 16, 0, 0),
        };
        buttons.Controls.Add(ok);

        var root = new TableLayoutPanel { ColumnCount = 1, AutoSize = true, Dock = DockStyle.Fill };
        root.Controls.Add(top);
        root.Controls.Add(buttons);
        Controls.Add(root);

        AcceptButton = ok;
        CancelButton = ok;
    }

    private static LinkLabel Link(string text, Action onClick)
    {
        var link = new LinkLabel { Text = text, AutoSize = true, Margin = new Padding(2, 2, 0, 2) };
        link.LinkClicked += (_, _) => onClick();
        return link;
    }

    private static void ShowInExplorer(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                Process.Start("explorer.exe", $"/select,\"{path}\"");
                return;
            }
            // No config yet (defaults in use) - open the folder instead,
            // creating it so there is somewhere to open.
            string folder = Path.GetDirectoryName(path)!;
            Directory.CreateDirectory(folder);
            Open(folder);
        }
        catch (Exception ex)
        {
            Log.Error($"Couldn't open {path}: {ex.Message}");
        }
    }

    private static void Open(string target)
    {
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Log.Error($"Couldn't open {target}: {ex.Message}");
        }
    }
}
