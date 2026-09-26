#ifndef SourceDir
  #error SourceDir define is required.
#endif

#ifndef OutputDir
  #error OutputDir define is required.
#endif

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

#define MyAppName "BugNarrator"
#define MyAppPublisher "ABD Enterprises"
#define MyAppExeName "BugNarrator.Windows.exe"

[Setup]
AppId={{6F8E7C0A-6A5E-4C4D-96B5-6B0F1E2F12A8}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=BugNarrator-windows-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
