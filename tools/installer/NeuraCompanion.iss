#define MyAppName "Neura Companion"
#define MyAppPublisher "VanTiger"
#define MyAppId "{{BCA35439-1D8B-4C4A-A970-9741E76EEA57}"
#define MySourceDir GetEnv("NEURA_INSTALLER_SOURCE")
#define MyOutputDir GetEnv("NEURA_INSTALLER_OUTPUT")
#define MyAppVersion GetEnv("NEURA_INSTALLER_VERSION")
#define MySafeVersion GetEnv("NEURA_INSTALLER_SAFE_VERSION")
#define MyAppExeName GetEnv("NEURA_INSTALLER_EXE")

#if MySourceDir == ""
  #error NEURA_INSTALLER_SOURCE was not supplied.
#endif
#if MyOutputDir == ""
  #error NEURA_INSTALLER_OUTPUT was not supplied.
#endif
#if MyAppVersion == ""
  #error NEURA_INSTALLER_VERSION was not supplied.
#endif
#if MySafeVersion == ""
  #error NEURA_INSTALLER_SAFE_VERSION was not supplied.
#endif
#if MyAppExeName == ""
  #error NEURA_INSTALLER_EXE was not supplied.
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Neura Companion
DefaultGroupName=Neura Companion
DisableProgramGroupPage=yes
DisableDirPage=no
OutputDir={#MyOutputDir}
OutputBaseFilename=NeuraCompanion_Setup_{#MySafeVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Neura Companion"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\Neura Companion"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Neura Companion"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent
