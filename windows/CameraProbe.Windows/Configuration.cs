using System.Text.Json;

namespace CameraProbe;

// Same schema as the macOS app and config.example.json:
//
// {
//   "relay":         { "enabled": true, "host": "onair.local",         "port": 80 },
//   "homeAssistant": { "enabled": true, "host": "homeassistant.local", "port": 8123 },
//   "ignoredApplications": []
// }
//
// Every field is optional - property initializers supply the defaults
// for anything omitted, so a partial config.json is valid.

sealed class RelayConfig
{
    public bool Enabled { get; set; } = true;
    public string Host { get; set; } = "onair.local";
    public int Port { get; set; } = 80;
}

sealed class HomeAssistantConfig
{
    public bool Enabled { get; set; } = true;
    public string Host { get; set; } = "homeassistant.local";
    public int Port { get; set; } = 8123;
}

sealed class AppConfig
{
    public RelayConfig Relay { get; set; } = new();
    public HomeAssistantConfig HomeAssistant { get; set; } = new();
    public List<string> IgnoredApplications { get; set; } = new();

    /// Replaces explicit JSON nulls ("relay": null) with defaults.
    public AppConfig Normalized()
    {
        Relay ??= new();
        HomeAssistant ??= new();
        IgnoredApplications ??= new();
        Relay.Host ??= new RelayConfig().Host;
        HomeAssistant.Host ??= new HomeAssistantConfig().Host;
        IgnoredApplications.RemoveAll(string.IsNullOrWhiteSpace);
        return this;
    }

    public AppConfig Clone() =>
        JsonSerializer.Deserialize<AppConfig>(JsonSerializer.Serialize(this, ConfigStore.JsonOptions), ConfigStore.JsonOptions)!;
}

// Holds the current config in memory behind a lock, so the Preferences
// window can replace it and every other part of the app sees the new
// values immediately, without a restart. Readers get a snapshot copy, so
// nothing outside this class can mutate the live config.
sealed class ConfigStore
{
    public static string FilePath => Path.Combine(AppInfo.DataDirectory, "config.json");

    internal static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        WriteIndented = true,
    };

    // Declared after JsonOptions on purpose: static initializers run in
    // source order, and the constructor loads the config using them.
    public static ConfigStore Shared { get; } = new();

    private readonly object _lock = new();
    private AppConfig _config;

    private ConfigStore()
    {
        _config = LoadFromDisk();
    }

    public AppConfig Config
    {
        get { lock (_lock) return _config.Clone(); }
    }

    /// Writes `newConfig` to disk and, only on success, makes it the live config.
    public void Save(AppConfig newConfig)
    {
        newConfig = newConfig.Clone().Normalized();
        Directory.CreateDirectory(AppInfo.DataDirectory);

        string temp = FilePath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(newConfig, JsonOptions));
        File.Move(temp, FilePath, overwrite: true);

        lock (_lock) _config = newConfig;
        Log.Info($"Configuration saved to {FilePath}");
    }

    public bool IsApplicationIgnored(params string?[] names)
    {
        List<string> ignored;
        lock (_lock) ignored = _config.IgnoredApplications;
        return names.Any(name => !string.IsNullOrEmpty(name) &&
            ignored.Any(i => string.Equals(i.Trim(), name, StringComparison.OrdinalIgnoreCase)));
    }

    private static AppConfig LoadFromDisk()
    {
        if (!File.Exists(FilePath))
        {
            Log.Info($"No config file at {FilePath}; using built-in defaults");
            return new AppConfig();
        }

        try
        {
            var config = JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(FilePath), JsonOptions);
            Log.Info($"Loaded configuration from {FilePath}");
            return (config ?? new AppConfig()).Normalized();
        }
        catch (Exception ex)
        {
            // A bad config file must never prevent startup - fall back to
            // defaults and make the failure loud instead.
            Log.Warn($"Failed to parse {FilePath}: {ex.Message}. Using built-in defaults.");
            return new AppConfig();
        }
    }
}
