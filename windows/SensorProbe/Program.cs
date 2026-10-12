// Throwaway prototype for step 2 of WINDOWS_PORT.md, take two.
//
// The CapabilityAccessManager registry keys turned out not to record webcam
// use on Windows 11 26H2 (build 26300), so this tries two other sources side
// by side:
//
//  [sensor]  Media Foundation's sensor activity monitor
//            (MFCreateSensorActivityMonitor) - per-device, per-process
//            streaming reports, which should give us the real app.
//  [evtlog]  The FrameServer operational event log - reliable on/off, but
//            no app identity. Used here as a cross-check so we can tell if
//            the sensor monitor ever misses a session.
//
// Usage: dotnet run [--verbose]   (--verbose dumps every raw report)

using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.Runtime.InteropServices;
using System.Text;
using SensorProbe;

bool verbose = args.Contains("--verbose");

Log("main", $"SensorProbe starting (pid {Environment.ProcessId}, OS {Environment.OSVersion.Version})");

int hr = Native.MFStartup(Native.MF_VERSION, 0);
Log("sensor", $"MFStartup hr=0x{hr:X8}");

var callback = new ReportCallback(verbose);
hr = Native.MFCreateSensorActivityMonitor(callback, out var monitor);
Log("sensor", $"MFCreateSensorActivityMonitor hr=0x{hr:X8}");
if (hr >= 0)
{
    hr = monitor.Start();
    Log("sensor", $"Start hr=0x{hr:X8}");
}

EventLogWatcher? watcher = null;
try
{
    var query = new EventLogQuery(
        "Microsoft-Windows-MF-FrameServer/Camera_FrameServer",
        PathType.LogName,
        "*[System[(EventID=11)]]");
    watcher = new EventLogWatcher(query);
    watcher.EventRecordWritten += (_, e) =>
    {
        using var record = e.EventRecord;
        if (record is null) return;
        string message;
        try { message = record.FormatDescription() ?? ""; } catch { return; }
        if (!message.Contains("TimerScope: FSStream")) return;
        var op = System.Text.RegularExpressions.Regex.Match(message, @"WatchdogOperation: (\w+)").Groups[1].Value;
        if (op is "Start" or "Stop")
            Log("evtlog", $"stream {op.ToUpperInvariant()} (FrameServer host pid {record.ProcessId})");
    };
    watcher.Enabled = true;
    Log("evtlog", "watching Camera_FrameServer log");
}
catch (Exception ex)
{
    Log("evtlog", $"could not watch event log: {ex.Message}");
}

Log("main", "Ready. Use the camera; Ctrl+C to quit.");

var quit = new ManualResetEventSlim();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; quit.Set(); };
quit.Wait();

if (hr >= 0) monitor.Stop();
watcher?.Dispose();
GC.KeepAlive(callback);

static void Log(string source, string message) =>
    Console.WriteLine($"{DateTime.Now:HH:mm:ss.fff} [{source}] {message}");

namespace SensorProbe
{
    [ComVisible(true)]
    sealed class ReportCallback(bool verbose) : IMFSensorActivitiesReportCallback
    {
        // Keyed by "symbolicLink|pid" -> description, for processes currently streaming.
        private Dictionary<string, string> _streaming = new();
        private bool _cameraOn;
        private int _reportCount;
        private readonly object _lock = new();

        public int OnActivitiesReport(IMFSensorActivitiesReport report)
        {
            try
            {
                lock (_lock) Handle(report);
            }
            catch (Exception ex)
            {
                Log($"callback error: {ex}");
            }
            return 0;
        }

        private void Handle(IMFSensorActivitiesReport report)
        {
            _reportCount++;
            report.GetCount(out uint deviceCount);
            var current = new Dictionary<string, string>();

            for (uint d = 0; d < deviceCount; d++)
            {
                report.GetActivityReport(d, out var device);
                string name = ReadString(device.GetFriendlyName);
                string link = ReadString(device.GetSymbolicLink);
                device.GetProcessCount(out uint processCount);

                if (verbose)
                    Log($"report #{_reportCount}: device \"{name}\" processes={processCount}");

                for (uint p = 0; p < processCount; p++)
                {
                    device.GetProcessActivity(p, out var activity);
                    activity.GetProcessId(out uint pid);
                    activity.GetStreamingState(out int streaming);
                    activity.GetStreamingMode(out int mode);
                    activity.GetReportTime(out long reportTime);

                    if (verbose)
                        Log($"    pid {pid} streaming={streaming != 0} mode={(mode == 0 ? "Controller" : "Shared")} " +
                            $"time={DateTime.FromFileTime(reportTime):HH:mm:ss.fff}");

                    if (streaming != 0)
                        current[$"{link}|{pid}"] = $"{Describe(pid)} on \"{name}\"";
                }
            }

            foreach (var (key, desc) in current)
                if (!_streaming.ContainsKey(key))
                    Log($"START  {desc}");
            foreach (var (key, desc) in _streaming)
                if (!current.ContainsKey(key))
                    Log($"STOP   {desc}");

            bool cameraOn = current.Count > 0;
            if (cameraOn != _cameraOn)
                Log($"=== CAMERA {(cameraOn ? "ON" : "OFF")} ===");

            _streaming = current;
            _cameraOn = cameraOn;
        }

        private delegate int StringGetter(StringBuilder buffer, uint capacity, out uint written);

        private static string ReadString(StringGetter getter)
        {
            var sb = new StringBuilder(1024);
            return getter(sb, (uint)sb.Capacity, out _) >= 0 ? sb.ToString() : "?";
        }

        private static string Describe(uint pid)
        {
            try
            {
                using var process = Process.GetProcessById((int)pid);
                string? path = null;
                try { path = process.MainModule?.FileName; } catch { }
                string? description = null;
                if (path is not null)
                {
                    try { description = FileVersionInfo.GetVersionInfo(path).FileDescription; } catch { }
                }
                return $"{process.ProcessName} (pid {pid}, desc \"{description}\", path {path ?? "?"})";
            }
            catch
            {
                return $"pid {pid} (exited)";
            }
        }

        private static void Log(string message) =>
            Console.WriteLine($"{DateTime.Now:HH:mm:ss.fff} [sensor] {message}");
    }

    static class Native
    {
        public const uint MF_VERSION = 0x00020070;

        [DllImport("mfplat.dll")]
        public static extern int MFStartup(uint version, uint flags);

        [DllImport("mfsensorgroup.dll")]
        public static extern int MFCreateSensorActivityMonitor(
            IMFSensorActivitiesReportCallback callback,
            out IMFSensorActivityMonitor monitor);
    }

    // Interface definitions from mfidl.h (Windows SDK).

    [ComImport, Guid("d0cef145-b3f4-4340-a2e5-7a5080ca05cb"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSensorActivityMonitor
    {
        [PreserveSig] int Start();
        [PreserveSig] int Stop();
    }

    [ComImport, Guid("de5072ee-dbe3-46dc-8a87-b6f631194751"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSensorActivitiesReportCallback
    {
        [PreserveSig] int OnActivitiesReport(IMFSensorActivitiesReport report);
    }

    [ComImport, Guid("683f7a5e-4a19-43cd-b1a9-dbf4ab3f7777"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSensorActivitiesReport
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetActivityReport(uint index, out IMFSensorActivityReport report);
        [PreserveSig] int GetActivityReportByDeviceName([MarshalAs(UnmanagedType.LPWStr)] string symbolicName, out IMFSensorActivityReport report);
    }

    [ComImport, Guid("3e8c4be1-a8c2-4528-90de-2851bde5fead"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSensorActivityReport
    {
        [PreserveSig] int GetFriendlyName([MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, uint capacity, out uint written);
        [PreserveSig] int GetSymbolicLink([MarshalAs(UnmanagedType.LPWStr)] StringBuilder link, uint capacity, out uint written);
        [PreserveSig] int GetProcessCount(out uint count);
        [PreserveSig] int GetProcessActivity(uint index, out IMFSensorProcessActivity activity);
    }

    [ComImport, Guid("39dc7f4a-b141-4719-813c-a7f46162a2b8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSensorProcessActivity
    {
        [PreserveSig] int GetProcessId(out uint pid);
        [PreserveSig] int GetStreamingState(out int streaming);
        [PreserveSig] int GetStreamingMode(out int mode);
        [PreserveSig] int GetReportTime(out long fileTime);
    }
}
