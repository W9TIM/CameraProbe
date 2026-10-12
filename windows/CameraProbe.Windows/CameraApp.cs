using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace CameraProbe;

/// A process using the camera. `Name` is what gets logged and sent to
/// Home Assistant: the exe's file description ("Zoom Meetings", "Google
/// Chrome") when it has one, otherwise the exe name without extension.
sealed record CameraApp(int Pid, string Name, string ExeName)
{
    /// ignoredApplications entries match the display name, the exe name,
    /// or the exe file name (e.g. "Zoom Meetings", "Zoom", "Zoom.exe").
    public bool IsIgnored =>
        ConfigStore.Shared.IsApplicationIgnored(Name, ExeName, ExeName + ".exe");

    public static CameraApp Resolve(int pid)
    {
        string? path = GetImagePath(pid);
        if (path is null)
        {
            // Couldn't open the process (exited, or protected). Fall back
            // to whatever Process can tell us.
            try
            {
                using var process = Process.GetProcessById(pid);
                return new CameraApp(pid, process.ProcessName, process.ProcessName);
            }
            catch
            {
                return new CameraApp(pid, "Unknown", "Unknown");
            }
        }

        string exeName = Path.GetFileNameWithoutExtension(path);
        string? description = null;
        try { description = FileVersionInfo.GetVersionInfo(path).FileDescription?.Trim(); } catch { }
        return new CameraApp(pid, string.IsNullOrEmpty(description) ? exeName : description, exeName);
    }

    // QueryFullProcessImageName with PROCESS_QUERY_LIMITED_INFORMATION works
    // for sandboxed browser processes, where Process.MainModule is denied.
    private static string? GetImagePath(int pid)
    {
        IntPtr handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (handle == IntPtr.Zero) return null;
        try
        {
            var buffer = new StringBuilder(1024);
            int size = buffer.Capacity;
            return QueryFullProcessImageName(handle, 0, buffer, ref size) ? buffer.ToString() : null;
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder exeName, ref int size);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
}
