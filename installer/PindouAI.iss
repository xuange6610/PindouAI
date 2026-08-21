#define MyAppName "拼豆 AI 设计"
#define MyAppVersion "2.8.10"
#define MyAppExeName "bead_ai_designer.exe"

[Setup]
AppId={{A38813CC-3C29-4C2A-8BB0-2732D527FCDF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=xuan
DefaultDirName={localappdata}\Programs\PindouAI
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=PindouAI-Windows-v2.8.10-x64-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=force

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; Excludes: "data\flutter_assets\%E7*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "artwork\*"; DestDir: "{app}\artwork"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
