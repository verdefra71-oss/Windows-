#define MyAppName "Preventivi"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef ReleaseDir
  #define ReleaseDir "build\windows\x64\runner\Release"
#endif
#define MyAppExeName "preventivi_app.exe"

[Setup]
AppId={{A7F4B6A5-5B0E-4C4A-9C3B-7E3C7E8D2B11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\Preventivi
DefaultGroupName=Preventivi
OutputDir=Output
OutputBaseFilename=Preventivi-Setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
SetupIconFile=..\assets\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Preventivi"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Preventivi"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Avvia Preventivi"; Flags: nowait postinstall skipifsilent
