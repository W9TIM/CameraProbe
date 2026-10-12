; Inno Setup script for CameraProbe for Windows.
; Build with windows\build-installer.ps1, which publishes the app and passes
; AppVersion / PublishDir in. Per-user install: no admin prompt.

#ifndef AppVersion
  #error AppVersion must be defined - build with windows\build-installer.ps1
#endif
#ifndef PublishDir
  #define PublishDir "..\publish"
#endif

[Setup]
AppId={{6B0E3C1A-5F4D-4E8B-9C2A-7D1E0F3B8A54}
AppName=CameraProbe
AppVersion={#AppVersion}
AppPublisher=Tim Smith
AppPublisherURL=https://github.com/W9TIM/CameraProbe
DefaultDirName={localappdata}\Programs\CameraProbe
DefaultGroupName=CameraProbe
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=CameraProbe-Setup-{#AppVersion}
SetupIconFile=..\CameraProbe.Windows\Assets\AppIcon.ico
UninstallDisplayIcon={app}\CameraProbe.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Matches AppInfo.InstanceMutexName (Local\com.tim.cameraprobe): setup and
; uninstall ask the user to quit CameraProbe first.
AppMutex=com.tim.cameraprobe
CloseApplications=yes

[Tasks]
Name: "startup"; Description: "Start CameraProbe when I sign in"; GroupDescription: "Options:"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\CameraProbe"; Filename: "{app}\CameraProbe.exe"

[Registry]
; Same Run value LoginItem.cs writes from Preferences, so the two agree.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "CameraProbe"; ValueData: """{app}\CameraProbe.exe"""; Tasks: startup
; Always remove it on uninstall, even if it was turned on from Preferences.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "CameraProbe"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\CameraProbe.exe"; Description: "Launch CameraProbe"; Flags: nowait postinstall skipifsilent

; The config and log in %APPDATA%\CameraProbe are deliberately left in place
; on uninstall, so reinstalling keeps your settings.

[Code]
// The app is framework-dependent: it needs the .NET 8 Desktop Runtime (x64).
function HasDesktopRuntime8: Boolean;
var
  FindRec: TFindRec;
begin
  Result := FindFirst(ExpandConstant('{commonpf64}\dotnet\shared\Microsoft.WindowsDesktop.App\8.*'), FindRec);
  if Result then
    FindClose(FindRec);
end;

function InitializeSetup: Boolean;
var
  ErrorCode: Integer;
begin
  Result := True;
  if not HasDesktopRuntime8 then
  begin
    if MsgBox('CameraProbe needs the .NET 8 Desktop Runtime (x64), which is not installed.' + #13#10#13#10 +
              'Open the download page now? Run this installer again afterwards.',
              mbConfirmation, MB_YESNO) = IDYES then
      ShellExec('open', 'https://dotnet.microsoft.com/download/dotnet/8.0', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
    Result := False;
  end;
end;
