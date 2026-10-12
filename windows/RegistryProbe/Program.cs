// Throwaway prototype for step 2 of WINDOWS_PORT.md: watch the webcam
// CapabilityAccessManager consent store and print every per-app change,
// so we can verify how the keys actually behave before building the real
// monitor on top of them.
//
// Usage: dotnet run [--interval-ms 1000]

using Microsoft.Win32;

const string ConsentPath =
    @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam";

int intervalMs = 1000;
int idx = Array.IndexOf(args, "--interval-ms");
if (idx >= 0 && idx + 1 < args.Length) intervalMs = int.Parse(args[idx + 1]);

var previous = new Dictionary<string, (long Start, long Stop)>();
bool first = true;

Console.WriteLine($"Watching HKCU and HKLM\\{ConsentPath} every {intervalMs} ms. Ctrl+C to quit.");

while (true)
{
    var current = Snapshot();

    foreach (var (key, value) in current)
    {
        previous.TryGetValue(key, out var old);
        bool isNew = !previous.ContainsKey(key);
        if (first || isNew || old != value)
        {
            string state = value.Start != 0 && value.Stop == 0 ? "IN USE" : "idle";
            string tag = first ? "initial" : isNew ? "NEW KEY" : "CHANGED";
            Console.WriteLine(
                $"{DateTime.Now:HH:mm:ss.fff} [{tag}] {state,-6} {FriendlyName(key)}\n" +
                $"    key   = {key}\n" +
                $"    start = {Format(value.Start)}  ({value.Start})\n" +
                $"    stop  = {Format(value.Stop)}  ({value.Stop})");
        }
    }

    foreach (var key in previous.Keys.Except(current.Keys))
        Console.WriteLine($"{DateTime.Now:HH:mm:ss.fff} [REMOVED] {key}");

    if (first)
    {
        int inUse = current.Values.Count(v => v.Start != 0 && v.Stop == 0);
        Console.WriteLine($"--- initial snapshot: {current.Count} app keys, {inUse} in use ---");
    }

    previous = current;
    first = false;
    Thread.Sleep(intervalMs);
}

static Dictionary<string, (long Start, long Stop)> Snapshot()
{
    var result = new Dictionary<string, (long Start, long Stop)>();
    foreach (var (hiveName, hive) in new[] { ("HKCU", Registry.CurrentUser), ("HKLM", Registry.LocalMachine) })
    {
        using var root = hive.OpenSubKey(ConsentPath);
        if (root is null) continue;

        foreach (var name in root.GetSubKeyNames())
        {
            if (name == "NonPackaged")
            {
                using var np = root.OpenSubKey(name);
                if (np is null) continue;
                foreach (var exe in np.GetSubKeyNames())
                {
                    using var k = np.OpenSubKey(exe);
                    if (k is not null) result[$@"{hiveName}\NonPackaged\{exe}"] = Read(k);
                }
            }
            else
            {
                using var k = root.OpenSubKey(name);
                if (k is not null) result[$@"{hiveName}\{name}"] = Read(k);
            }
        }
    }
    return result;
}

static (long, long) Read(RegistryKey k) =>
    (Convert.ToInt64(k.GetValue("LastUsedTimeStart") ?? 0L),
     Convert.ToInt64(k.GetValue("LastUsedTimeStop") ?? 0L));

static string Format(long fileTime) =>
    fileTime == 0 ? "0" : DateTime.FromFileTime(fileTime).ToString("yyyy-MM-dd HH:mm:ss.fff");

static string FriendlyName(string key)
{
    string last = key[(key.LastIndexOf('\\') + 1)..];
    if (key.Contains(@"\NonPackaged\"))
        return Path.GetFileNameWithoutExtension(last.Replace('#', '\\'));
    int underscore = last.LastIndexOf('_');
    return underscore > 0 ? last[..underscore] : last;
}
