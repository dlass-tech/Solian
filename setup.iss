; ==================================================
#define AppVersion "3.3.0"
#define BuildNumber "144"
; ==================================================

#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppName=呆兮
AppVersion={#AppVersion}
AppPublisher=zhaishis
AppPublisherURL=https://zhaishis.com
AppSupportURL=https://zhaishis.com
AppUpdatesURL=https://github.com/dlass-tech/Solian/releases
AppCopyright=Copyright © 2026 zhaishis
VersionInfoVersion={#FullVersion}
UninstallDisplayName=每刻
UninstallDisplayIcon={app}\dyci.exe

DefaultDirName={commonpf}\dyci
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
Name: "{group}\dyci"; Filename: "{app}\dyci.exe";IconFilename: "{app}\dyci.exe"
Name: "{group}\{cm:UninstallProgram,Solian}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\dyci"; Filename: "{app}\dyci.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\dyci.exe"; Description: "启动每刻社区"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\zhaishis\dyci"
Type: files; Name: "{group}\每刻.lnk" ;
Type: files; Name: "{autodesktop}\每刻.lnk" ;
