namespace CameraProbe;

// Windows counterpart of the macOS OSLog logger: appends to
// %APPDATA%\CameraProbe\CameraProbe.log. The file is rolled over to
// CameraProbe.old.log at startup once it passes 1 MB, so it never grows
// without bound. Logging must never take the app down, so every failure
// here is swallowed.
static class Log
{
    private const long MaxBytes = 1024 * 1024;
    private static readonly object Lock = new();

    public static string FilePath { get; } = Path.Combine(AppInfo.DataDirectory, "CameraProbe.log");

    public static void Initialize()
    {
        try
        {
            Directory.CreateDirectory(AppInfo.DataDirectory);
            var info = new FileInfo(FilePath);
            if (info.Exists && info.Length > MaxBytes)
                File.Move(FilePath, Path.Combine(AppInfo.DataDirectory, "CameraProbe.old.log"), overwrite: true);
        }
        catch
        {
        }
    }

    public static void Info(string message) => Write("INFO ", message);
    public static void Warn(string message) => Write("WARN ", message);
    public static void Error(string message) => Write("ERROR", message);

    private static void Write(string level, string message)
    {
        string line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {level} {message}";
        System.Diagnostics.Debug.WriteLine(line);
        lock (Lock)
        {
            try
            {
                File.AppendAllText(FilePath, line + Environment.NewLine);
            }
            catch
            {
            }
        }
    }
}
