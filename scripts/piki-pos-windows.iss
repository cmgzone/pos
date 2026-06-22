; Piki POS Windows Installer - Inno Setup script
;
; Build the installer with:
;   "C:\Users\Admin\AppData\Local\Programs\Inno Setup 6\ISCC.exe" scripts\piki-pos-windows.iss
;
; This packages the entire Flutter Windows Release folder (pos_app.exe + all
; plugin DLLs + data folder) into a single setup.exe that users install via
; a standard Windows installer wizard with shortcuts and an uninstaller.

#define MyAppName "Piki POS"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Piki POS"
#define MyAppURL "https://pikipos.com"
#define MyAppExeName "pos_app.exe"

[Setup]
AppId={{B8F3A2E1-7C4D-4E9F-A1B6-3D5E8F9C2A74}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\build\windows-packages
OutputBaseFilename=piki-pos-windows-{#MyAppVersion}-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: checkedonce

[Files]
; Copy the entire Flutter Release folder - this includes pos_app.exe, all
; plugin DLLs (connectivity_plus_plugin.dll, flutter_windows.dll, isar.dll,
; sqlite3.dll, etc.) and the data/ folder with Flutter assets.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Kill the app if it's running before uninstalling
Filename: "{cmd}"; Parameters: "/C taskkill /IM {#MyAppExeName} /F"; Flags: runhidden; RunOnceId: "KillApp"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
