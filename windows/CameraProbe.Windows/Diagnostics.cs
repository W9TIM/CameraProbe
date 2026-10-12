using System.Net;
using System.Runtime.InteropServices;

namespace CameraProbe;

// Backs --test, --status, --help and --version. These run as a one-off
// CLI invocation and exit before any UI is shown.
static class Diagnostics
{
    private sealed record CheckResult(string Label, bool Passed, string? Detail = null);

    public static int Run(HashSet<string> flags)
    {
        ConsoleHost.Attach();
        try
        {
            if (flags.Contains("--version")) { Console.WriteLine($"{AppInfo.Name} {AppInfo.Version}"); return 0; }
            if (flags.Contains("--help")) { PrintUsage(); return 0; }
            if (flags.Contains("--status")) { PrintStatus(); return 0; }
            if (flags.Contains("--test")) return RunSelfTest() ? 0 : 1;

            Console.WriteLine($"Unknown option: {string.Join(" ", flags)}\n");
            PrintUsage();
            return 2;
        }
        finally
        {
            ConsoleHost.Detach();
        }
    }

    public static bool IsMonitorRunning() =>
        Mutex.TryOpenExisting(AppInfo.InstanceMutexName, out var mutex) && Dispose(mutex);

    private static bool Dispose(IDisposable d) { d.Dispose(); return true; }

    private static bool RunSelfTest()
    {
        Console.WriteLine($"{AppInfo.Name} {AppInfo.Version} - self test\n");
        var config = ConfigStore.Shared.Config;
        var results = new List<CheckResult>
        {
            CheckDns(config.Relay.Host),
            CheckDns(config.HomeAssistant.Host),
        };

        if (config.Relay.Enabled)
            results.Add(CheckHttp("Relay reachability", config.Relay.Host, config.Relay.Port));
        if (config.HomeAssistant.Enabled)
            results.Add(CheckHttp("Home Assistant reachability", config.HomeAssistant.Host, config.HomeAssistant.Port));

        results.Add(CheckCameraAccess());
        results.Add(new CheckResult("Start at Login", true, LoginItemDetail()));
        results.Add(new CheckResult("CameraProbe running", IsMonitorRunning()));

        foreach (var r in results)
            Console.WriteLine($"{Padded(r.Label)} {(r.Passed ? "OK" : "FAIL")}{(string.IsNullOrEmpty(r.Detail) ? "" : $" ({r.Detail})")}");

        int failed = results.Count(r => !r.Passed);
        Console.WriteLine();
        Console.WriteLine(failed == 0 ? "All checks passed." : $"{failed} check(s) failed.");
        Console.WriteLine($"Config: {ConfigStore.FilePath}");
        Console.WriteLine($"Log:    {Log.FilePath}");
        return failed == 0;
    }

    private static void PrintStatus()
    {
        Console.WriteLine($"{AppInfo.Name} {AppInfo.Version}\n");
        var config = ConfigStore.Shared.Config;

        string relay = config.Relay.Enabled
            ? (CheckHttp("Relay", config.Relay.Host, config.Relay.Port).Passed ? "OK" : "FAIL")
            : "disabled";
        string homeAssistant = config.HomeAssistant.Enabled
            ? (CheckHttp("Home Assistant", config.HomeAssistant.Host, config.HomeAssistant.Port).Passed ? "OK" : "FAIL")
            : "disabled";

        Console.WriteLine($"{Padded("Relay", 20)} {relay}");
        Console.WriteLine($"{Padded("Home Assistant", 20)} {homeAssistant}");
        Console.WriteLine($"{Padded("Start at Login", 20)} {LoginItemDetail()}");
        Console.WriteLine($"{Padded("Camera Monitor", 20)} {(IsMonitorRunning() ? "Running" : "Not running")}");
    }

    private static void PrintUsage()
    {
        Console.WriteLine($"""
            {AppInfo.Name} {AppInfo.Version}

            Usage:
              CameraProbe                Launch the tray app (splash screen, then runs in the notification area)
              CameraProbe --status       Show whether CameraProbe is running and reachable
              CameraProbe --test         Run diagnostics: DNS, relay, Home Assistant, camera access, Start at Login
              CameraProbe --version      Print the version
              CameraProbe --help         Show this message

            Preferences (relay, Home Assistant, ignored apps, Start at Login) are
            edited from the app's tray icon, not from the command line.
            Config file: {ConfigStore.FilePath}
            """);
    }

    private static CheckResult CheckDns(string host)
    {
        try
        {
            var addresses = Dns.GetHostAddresses(host);
            return new CheckResult($"DNS ({host})", addresses.Length > 0, string.Join(", ", addresses.Select(a => a.ToString())));
        }
        catch (Exception ex)
        {
            return new CheckResult($"DNS ({host})", false, ex.Message);
        }
    }

    // Any HTTP response at all counts as reachable, same as macOS.
    private static CheckResult CheckHttp(string label, string host, int port)
    {
        try
        {
            using var response = Notifier.Http.GetAsync($"http://{host}:{port}/").GetAwaiter().GetResult();
            return new CheckResult(label, true, $"HTTP {(int)response.StatusCode}");
        }
        catch (Exception ex)
        {
            return new CheckResult(label, false, ex is TaskCanceledException ? "timed out" : ex.Message);
        }
    }

    private static CheckResult CheckCameraAccess()
    {
        try
        {
            using var monitor = new SensorActivityMonitor(_ => { });
            monitor.Start();
            return new CheckResult("Camera detection access", true);
        }
        catch (Exception ex)
        {
            return new CheckResult("Camera detection access", false, ex.Message);
        }
    }

    private static string LoginItemDetail() =>
        !LoginItem.IsEnabled ? "Disabled"
        : LoginItem.PointsAtThisExe ? "Enabled"
        : $"Enabled, but points at {LoginItem.RegisteredCommand}";

    private static string Padded(string label, int width = 34) =>
        label.Length >= width ? label : label.PadRight(width, '.');
}

// CameraProbe is a GUI (WinExe) app so it never flashes a console window
// at login; for the CLI flags it borrows the console of whatever launched
// it instead.
static class ConsoleHost
{
    private const int AttachParentProcess = -1;

    public static void Attach()
    {
        if (AttachConsole(AttachParentProcess))
            Console.WriteLine();  // the shell has already printed its prompt
    }

    public static void Detach()
    {
        Console.Out.Flush();
        FreeConsole();
    }

    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int processId);

    [DllImport("kernel32.dll")]
    private static extern bool FreeConsole();
}
