#define MyAppVersion "2.8.10"
#define MyAppExeName "bead_ai_designer.exe"

#ifndef BuildRoot
  #define BuildRoot "..\build\windows\x64\runner\Release"
#endif

#ifdef LiteBuild
  #define MyAppName "拼豆 AI 设计 Lite"
  #define MyAppId "{{2B1C451D-4F28-4DDC-99B3-791C8D47E82B}"
  #define MyInstallDir "PindouAI-Lite"
  #define MyOutputName "PindouAI-Windows-v2.8.10-x64-Lite-Setup"
#else
  #define MyAppName "拼豆 AI 设计"
  #define MyAppId "{{A38813CC-3C29-4C2A-8BB0-2732D527FCDF}"
  #define MyInstallDir "PindouAI"
  #define MyOutputName "PindouAI-Windows-v2.8.10-x64-Setup"
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=xuan
DefaultDirName={localappdata}\Programs\{#MyInstallDir}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename={#MyOutputName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
CloseApplications=force

[Files]
Source: "{#BuildRoot}\*"; Excludes: "data\flutter_assets\%E7*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifndef LiteBuild
Source: "artwork\*"; DestDir: "{app}\artwork"; Flags: ignoreversion recursesubdirs createallsubdirs
#endif

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
