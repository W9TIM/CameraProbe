namespace CameraProbe;

// Icons embedded from Assets/ (regenerate with windows/make-icons.ps1).
//
// Windows has no equivalent of the macOS overlay subview for the red dot,
// so the tray swaps between two icons instead: TrayIdle (tally light unlit)
// and TrayActive (tally light glowing red). Each .ico carries 16-48px
// frames; loading at the system's small-icon size picks the crisp one for
// the current display scaling.
sealed class TrayIcons : IDisposable
{
    public Icon Plain { get; }
    public Icon WithDot { get; }

    public TrayIcons()
    {
        Plain = LoadIcon("TrayIdle.ico", SystemInformation.SmallIconSize);
        WithDot = LoadIcon("TrayActive.ico", SystemInformation.SmallIconSize);
    }

    /// The full app icon (title bars, About), at the closest available size.
    public static Icon AppIcon(Size size) => LoadIcon("AppIcon.ico", size);

    /// The 256px app artwork, for the splash screen.
    public static Bitmap AppArtwork()
    {
        using var stream = OpenResource("AppIcon256.png");
        return new Bitmap(stream);
    }

    private static Icon LoadIcon(string name, Size size)
    {
        using var stream = OpenResource(name);
        return new Icon(stream, size);
    }

    private static Stream OpenResource(string name) =>
        typeof(TrayIcons).Assembly.GetManifestResourceStream(name)
        ?? throw new InvalidOperationException($"Missing embedded resource {name}");

    public void Dispose()
    {
        Plain.Dispose();
        WithDot.Dispose();
    }
}
