// See CameraProbe.Cli.csproj for why this exists. With no arguments it just
// launches the tray app like CameraProbe.exe would.

static class Program
{
    [STAThread]
    static int Main(string[] args) => CameraProbe.Program.Main(args);
}
