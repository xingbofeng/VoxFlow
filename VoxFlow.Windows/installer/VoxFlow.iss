#ifndef PublishDir
  #error PublishDir must point to the verified self-contained win-x64 publish directory.
#endif
#ifndef OutputDir
  #error OutputDir must point to the release artifact directory.
#endif
#ifndef AppVersion
  #error AppVersion must be supplied by prepare-windows-release.ps1.
#endif

#define AppName "VoxFlow"
#define AppExeName "VoxFlow.exe"

[Setup]
AppId={{DDC46BC7-A391-42E0-B9FC-24C944A9E72C}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=VoxFlow contributors
AppPublisherURL=https://github.com/xingbofeng/VoxFlow
AppSupportURL=https://github.com/xingbofeng/VoxFlow/issues
DefaultDirName={localappdata}\Programs\VoxFlow
DefaultGroupName=VoxFlow
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible and not arm64
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=VoxFlow-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}
CloseApplications=yes
RestartApplications=no
ChangesEnvironment=no
VersionInfoVersion={#AppVersion}

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Required release artifacts are intentionally named here so source-contract
; checks fail before compilation if their packaging contract changes:
; qwen_asr.dll
; runtime\ffmpeg\ffmpeg.exe
; runtime\ffmpeg\ffprobe.exe
; runtime\ffmpeg\FFMPEG_RUNTIME_MANIFEST.json
; runtime\ffmpeg\LICENSE.txt
; licenses\LICENSE-GPL-3.0-or-later.txt
; licenses\LICENSE-qwen-asr-MIT.txt
; licenses\THIRD-PARTY-NOTICES.md

[Icons]
Name: "{autoprograms}\VoxFlow"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\VoxFlow"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch VoxFlow"; Flags: nowait postinstall skipifsilent

[Code]
var
  deleteuserdata: TNewCheckBox;

procedure InitializeUninstallProgressForm();
begin
  deleteuserdata := TNewCheckBox.Create(UninstallProgressForm);
  deleteuserdata.Parent := UninstallProgressForm;
  deleteuserdata.Left := UninstallProgressForm.StatusLabel.Left;
  deleteuserdata.Top := UninstallProgressForm.StatusLabel.Top + UninstallProgressForm.StatusLabel.Height + ScaleY(16);
  deleteuserdata.Width := UninstallProgressForm.ClientWidth - (deleteuserdata.Left * 2);
  deleteuserdata.Height := ScaleY(42);
  deleteuserdata.WordWrap := True;
  deleteuserdata.Caption := 'Also permanently delete settings, history, logs, and downloaded models from %LOCALAPPDATA%\VoxFlow';
  deleteuserdata.Checked := False;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and deleteuserdata.Checked then
  begin
    if MsgBox(
      'Deleting VoxFlow user data cannot be undone. Continue?',
      mbConfirmation,
      MB_YESNO) <> IDYES then
      deleteuserdata.Checked := False;
  end;

  if (CurUninstallStep = usPostUninstall) and deleteuserdata.Checked then
    DelTree(ExpandConstant('{localappdata}\VoxFlow'), True, True, True);
end;
