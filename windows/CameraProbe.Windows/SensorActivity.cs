using System.Runtime.InteropServices;
using System.Text;

namespace CameraProbe;

// Thin wrapper over Media Foundation's sensor activity monitor
// (MFCreateSensorActivityMonitor). Windows calls back on its own worker
// thread with a report covering every camera device and each process
// using it; this flattens that into the set of PIDs currently streaming
// from any camera.
//
// Chosen over the CapabilityAccessManager registry keys and the
// FrameServer event log after testing - see WINDOWS_PORT.md.
sealed class SensorActivityMonitor : IDisposable
{
    private readonly ReportCallback _callback;
    private IMFSensorActivityMonitor? _monitor;
    private bool _mfStarted;

    public SensorActivityMonitor(Action<IReadOnlyList<int>> onReport)
    {
        _callback = new ReportCallback(onReport);
    }

    /// Throws if Media Foundation or the monitor can't be started.
    public void Start()
    {
        Check(Native.MFStartup(Native.MF_VERSION, 0), "MFStartup");
        _mfStarted = true;
        Check(Native.MFCreateSensorActivityMonitor(_callback, out var monitor), "MFCreateSensorActivityMonitor");
        _monitor = monitor;
        Check(monitor.Start(), "IMFSensorActivityMonitor.Start");
    }

    public void Dispose()
    {
        if (_monitor is not null)
        {
            _monitor.Stop();
            Marshal.ReleaseComObject(_monitor);
            _monitor = null;
        }
        if (_mfStarted)
        {
            Native.MFShutdown();
            _mfStarted = false;
        }
    }

    private static void Check(int hr, string what)
    {
        if (hr < 0) throw new InvalidOperationException($"{what} failed (hr=0x{hr:X8})");
    }

    [ComVisible(true)]
    private sealed class ReportCallback(Action<IReadOnlyList<int>> onReport) : IMFSensorActivitiesReportCallback
    {
        public int OnActivitiesReport(IMFSensorActivitiesReport report)
        {
            try
            {
                var pids = new List<int>();
                report.GetCount(out uint deviceCount);
                for (uint d = 0; d < deviceCount; d++)
                {
                    if (report.GetActivityReport(d, out var device) < 0) continue;
                    device.GetProcessCount(out uint processCount);
                    for (uint p = 0; p < processCount; p++)
                    {
                        if (device.GetProcessActivity(p, out var activity) < 0) continue;
                        activity.GetStreamingState(out int streaming);
                        activity.GetProcessId(out uint pid);
                        if (streaming != 0 && !pids.Contains((int)pid)) pids.Add((int)pid);
                    }
                }
                onReport(pids);
            }
            catch (Exception ex)
            {
                Log.Error($"Sensor activity report failed: {ex}");
            }
            return 0;
        }
    }

    private static class Native
    {
        public const uint MF_VERSION = 0x00020070;

        [DllImport("mfplat.dll")]
        public static extern int MFStartup(uint version, uint flags);

        [DllImport("mfplat.dll")]
        public static extern int MFShutdown();

        [DllImport("mfsensorgroup.dll")]
        public static extern int MFCreateSensorActivityMonitor(
            IMFSensorActivitiesReportCallback callback,
            out IMFSensorActivityMonitor monitor);
    }
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
