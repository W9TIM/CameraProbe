namespace CameraProbe;

public static class Program
{
    // Public so the CameraProbe.com console shim (CameraProbe.Cli) can call it.
    [STAThread]
    public static int Main(string[] args)
    {
        Log.Initialize();

        // CLI flags are handled before any UI is shown, then we exit.
        if (args.Length > 0)
            return Diagnostics.Run(new HashSet<string>(args, StringComparer.OrdinalIgnoreCase));

        using var instance = new Mutex(initiallyOwned: true, AppInfo.InstanceMutexName, out bool createdNew);
        if (!createdNew)
        {
            MessageBox.Show($"{AppInfo.Name} is already running. Look for its icon in the notification area.",
                AppInfo.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
        return 0;
    }
}
