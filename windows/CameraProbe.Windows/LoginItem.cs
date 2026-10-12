using Microsoft.Win32;

namespace CameraProbe;

// Start at Login via HKCU\Software\Microsoft\Windows\CurrentVersion\Run -
// per-user, no admin rights needed, and it shows up in Task Manager's
// Startup apps page like any other app.
static class LoginItem
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private static string Command => $"\"{Environment.ProcessPath}\"";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            return key?.GetValue(AppInfo.Name) is string;
        }
    }

    /// The registered command, if any - may point at a different copy of
    /// the exe than the one currently running (e.g. a dev build).
    public static string? RegisteredCommand
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            return key?.GetValue(AppInfo.Name) as string;
        }
    }

    public static bool PointsAtThisExe =>
        string.Equals(RegisteredCommand, Command, StringComparison.OrdinalIgnoreCase);

    public static bool SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (enabled)
                key.SetValue(AppInfo.Name, Command);
            else
                key.DeleteValue(AppInfo.Name, throwOnMissingValue: false);
            Log.Info($"Start at Login set to {enabled}");
            return true;
        }
        catch (Exception ex)
        {
            Log.Error($"Failed to update Start at Login: {ex.Message}");
            return false;
        }
    }
}
