; DIY.CAD Windows installer script (Inno Setup 6). Compiled by Paketle.bat.
; Installs per user (no admin rights needed); the OpenCASCADE environment (occ_env) is optionally set up in the
; install folder with OCC_Kur.bat.

#define AppName "DIY.CAD"
#define AppVersion "0.9.3"
#define AppExe "DIY.CAD.exe"

[Setup]
AppId={{5C1B7E52-9A4D-4C61-8E0F-2D7A3B9C4E11}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=DIY.CAD
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=DIY.CAD-{#AppVersion}-setup
SetupIconFile=..\icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "assoc"; Description: "Open .dcad / .dasm files with DIY.CAD"; GroupDescription: "File association"
Name: "occ"; Description: "Install the OpenCASCADE (B-rep) kernel — requires Python 3.11–3.13, downloads ~240 MB"; GroupDescription: "Optional"; Flags: unchecked

[Files]
Source: "..\build\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\DIY.CAD.console.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\occ\*.py"; DestDir: "{app}\occ"; Flags: ignoreversion
Source: "..\macros\*.gd"; DestDir: "{app}\macros"; Flags: ignoreversion
Source: "..\plugins\*.gd"; DestDir: "{app}\plugins"; Flags: ignoreversion
Source: "..\OCC_Kur.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Install OpenCASCADE kernel"; Filename: "{app}\OCC_Kur.bat"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\.dcad"; ValueType: string; ValueName: ""; ValueData: "DIYCAD.Part"; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\DIYCAD.Part"; ValueType: string; ValueName: ""; ValueData: "DIY.CAD Part"; Flags: uninsdeletekey; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\DIYCAD.Part\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\DIYCAD.Part\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\.dasm"; ValueType: string; ValueName: ""; ValueData: "DIYCAD.Assembly"; Flags: uninsdeletevalue; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\DIYCAD.Assembly"; ValueType: string; ValueName: ""; ValueData: "DIY.CAD Assembly"; Flags: uninsdeletekey; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\DIYCAD.Assembly\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"; Tasks: assoc
Root: HKCU; Subkey: "Software\Classes\DIYCAD.Assembly\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: assoc

[Run]
Filename: "{app}\OCC_Kur.bat"; WorkingDir: "{app}"; Description: "OpenCASCADE setup"; Tasks: occ; Flags: shellexec waituntilterminated
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\occ_env"
Type: filesandordirs; Name: "{app}\occ\__pycache__"
