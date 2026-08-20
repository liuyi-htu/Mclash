#define MyAppName "Mclash"
#ifndef MyAppVersion
#define MyAppVersion "1.0.2"
#endif
#ifndef MyBuildNumber
#define MyBuildNumber "1"
#endif
#define MyPackageVersion MyAppVersion + "+" + MyBuildNumber
#define MyFileVersion MyAppVersion + "." + MyBuildNumber
#define MyAppExeName "Mclash.exe"

[Setup]
AppId={{6C93D89B-75B0-4AE7-A8F3-A0F98048B215}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyFileVersion}
DefaultDirName={autopf}\Mclash
DefaultGroupName=Mclash
OutputDir=Output
OutputBaseFilename=Mclash-Windows-Setup-{#MyPackageVersion}-x64
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Mclash.ico
SetupIconFile=..\mclash\windows\runner\resources\app_icon.ico

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Dirs]
Name: "{app}\data"; Permissions: users-modify
Name: "{app}\data\profiles"; Permissions: users-modify
Name: "{app}\data\logs"; Permissions: users-modify
Name: "{app}\data\rulesets"; Permissions: users-modify

[Files]
Source: "..\mclash\build\windows\x64\runner\Release\*"; Excludes: "MclashService.exe,mihomoService.exe,mihomo.exe,sing-box.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\windows-package\MclashService.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\windows-package\mihomo.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\windows-package\sing-box.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\windows-package\downloaded-config.yaml"; DestDir: "{app}\data"; DestName: "config.yaml"; Flags: onlyifdoesntexist
Source: "..\windows-package\geosite.dat"; DestDir: "{app}\data"; DestName: "GeoSite.dat"; Flags: onlyifdoesntexist
Source: "..\windows-package\geoip.dat"; DestDir: "{app}\data"; DestName: "GeoIP.dat"; Flags: onlyifdoesntexist
Source: "..\windows-package\country.mmdb"; DestDir: "{app}\data"; DestName: "Country.mmdb"; Flags: onlyifdoesntexist
Source: "..\windows-package\rulesets\*.srs"; DestDir: "{app}\data\rulesets"; Flags: ignoreversion
Source: "..\mclash\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; DestName: "Mclash.ico"; Flags: ignoreversion

[Icons]
Name: "{group}\Mclash"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Mclash.ico"
Name: "{autodesktop}\Mclash"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Mclash.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\MclashService.exe"; Parameters: "install --base ""{app}"" --data-dir ""{app}\data"""; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Mclash"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\MclashService.exe"; Parameters: "stop --base ""{app}"" --data-dir ""{app}\data"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "StopMclashService"
Filename: "{app}\MclashService.exe"; Parameters: "restore-system-proxy --base ""{app}"" --data-dir ""{app}\data"" --proxy-backup ""{localappdata}\Mclash\system-proxy-backup.json"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "RestoreMclashSystemProxy"
Filename: "{app}\MclashService.exe"; Parameters: "uninstall --base ""{app}"" --data-dir ""{app}\data"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "RemoveMclashService"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{commonappdata}\Mclash"
Type: files; Name: "{app}\mihomoService.exe"
