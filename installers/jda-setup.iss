; Jda Programming Language — Windows Installer (Inno Setup)
; Build: iscc installers/jda-setup.iss
; Requires: Inno Setup 6+ (https://jrsoftware.org/isinfo.php)

#define MyAppName "Jda Programming Language"
#define MyAppVersion GetEnv('JDA_VERSION')
#if MyAppVersion == ""
#define MyAppVersion "0.2.0"
#endif
#define MyAppPublisher "Jda Language Team"
#define MyAppURL "https://github.com/jdalang/jda-lang"

[Setup]
AppId={{B3A7F1E2-8C4D-4F6A-9E2B-1D3C5F8A7B9E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
DefaultDirName={autopf}\Jda
DefaultGroupName=Jda
AllowNoIcons=yes
OutputDir=..\dist
OutputBaseFilename=jda-{#MyAppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ChangesEnvironment=yes
SetupIconFile=jda-icon.ico
UninstallDisplayIcon={app}\jda-icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Compiler binary (Linux ELF — runs in WSL2)
Source: "..\bootstrap\bin\jda1-bootstrap"; DestDir: "{app}\bin"; DestName: "jda1"; Flags: ignoreversion
; Stdlib
Source: "..\stdlib\*.jda"; DestDir: "{app}\stdlib"; Flags: ignoreversion recursesubdirs
Source: "..\stdlib\net\*.jda"; DestDir: "{app}\stdlib\net"; Flags: ignoreversion
; Tools
Source: "..\tools\jda"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "..\tools\*.sh"; DestDir: "{app}\tools"; Flags: ignoreversion
; Version
Source: "..\VERSION"; DestDir: "{app}"; Flags: ignoreversion
; Wrapper scripts
Source: "windows\jda.cmd"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "windows\jda.ps1"; DestDir: "{app}\bin"; Flags: ignoreversion

[Icons]
Name: "{group}\Jda Command Prompt"; Filename: "{cmd}"; Parameters: "/k set PATH={app}\bin;%PATH%"; WorkingDir: "{userdocs}"
Name: "{group}\Uninstall Jda"; Filename: "{uninstallexe}"

[Registry]
; Add to system PATH
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\bin"; \
    Check: NeedsAddPath('{app}\bin')

[Run]
Filename: "{cmd}"; Parameters: "/c jda.cmd version"; WorkingDir: "{app}\bin"; \
    Description: "Verify installation"; Flags: postinstall shellexec waituntilterminated

[Code]
function NeedsAddPath(Param: string): Boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
    'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'Path', OrigPath) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Param + ';', ';' + OrigPath + ';') = 0;
end;
