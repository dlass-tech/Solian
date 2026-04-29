; ==================================================
#define AppVersion "3.3.0"
#define BuildNumber "144"
; ==================================================
#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppName=Dynamic
AppVersion={#AppVersion}
AppPublisher=zhaishis
AppPublisherURL=https://zhaishis.com
AppSupportURL=https://zhaishis.com
AppUpdatesURL=https://github.com/dlass-tech/Solian/releases
AppCopyright=Copyright © 2026 zhaishis
VersionInfoVersion={#FullVersion}
UninstallDisplayName=Dynamic
UninstallDisplayIcon={app}\Dynamic.exe
DefaultDirName={commonpf}\Dynamic
UsePreviousAppDir=no
OutputDir=.\Installer
OutputBaseFilename=windows-x86_64-setup
SetupIconFile=.\assets\icons\icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4
ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin

[Files]
Source: ".\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Dynamic"; Filename: "{app}\Dynamic.exe"; IconFilename: "{app}\Dynamic.exe"
Name: "{group}\{cm:UninstallProgram,Dynamic}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Dynamic"; Filename: "{app}\Dynamic.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\Dynamic.exe"; Description: "启动每刻社区"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\zhaishis\Dynamic"
Type: files; Name: "{group}\Dynamic.lnk"
Type: files; Name: "{autodesktop}\Dynamic.lnk"
