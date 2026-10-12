using System.Reflection;

namespace CameraProbe;

static class AppInfo
{
    public const string Name = "CameraProbe";
    public const string Label = "com.tim.cameraprobe";

    // Named mutex used both as the single-instance guard and by
    // --status/--test to tell whether the tray app is running.
    public const string InstanceMutexName = @"Local\" + Label;

    public static string Version { get; } =
        Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion.Split('+')[0] ?? "0.0.0";

    public static string DataDirectory { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), Name);
}
