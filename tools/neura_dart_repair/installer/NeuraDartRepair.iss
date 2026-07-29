#define MyAppName "Neura Dart Repair"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Neura"
#define MyAppExeName "RUN_NEURA_REPAIR.cmd"

[Setup]
AppId={{B48AD652-8D7A-4CC0-A27E-CF8826D21E26}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Neura Dart Repair
DefaultGroupName=Neura
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=Neura_Dart_Repair_Setup_v1_0_0
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "installer\output\*"

[Icons]
Name: "{group}\Neura Dart Repair"; Filename: "{cmd}"; Parameters: "/c ""{app}\RUN_NEURA_REPAIR.cmd"""; WorkingDir: "{app}"
Name: "{autodesktop}\Neura Dart Repair"; Filename: "{cmd}"; Parameters: "/c ""{app}\RUN_NEURA_REPAIR.cmd"""; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{cmd}"; Parameters: "/c ""{app}\RUN_NEURA_REPAIR.cmd"""; Description: "Run Neura Dart Repair"; Flags: postinstall nowait skipifsilent
