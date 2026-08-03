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
SetupIconFile=..\src\VoxFlow.Windows.App\Assets\VoxFlow.ico
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
; Qwen\QWEN_NATIVE_RUNTIME_MANIFEST.json
; Qwen\MODEL_PROVENANCE.json
; Qwen\readiness-canary.wav
; ScreenCapture.NET.dll
; ScreenCapture.NET.DX11.dll
; HPPH.dll
; Vortice.Direct3D11.dll
; Vortice.DXGI.dll
; SharpGen.Runtime.dll
; runtime\ffmpeg\ffmpeg.exe
; runtime\ffmpeg\ffprobe.exe
; runtime\ffmpeg\FFMPEG_RUNTIME_MANIFEST.json
; runtime\ffmpeg\THIRD_PARTY_NOTICES.md
; runtime\agent\voxflow-agent.exe
; runtime\agent\VOXFLOW_AGENT_RUNTIME_MANIFEST.json
; runtime\ocr\tesseract.exe
; runtime\ocr\TESSERACT_RUNTIME_MANIFEST.json
; runtime\ocr\LICENSE.txt
; runtime\ocr\tessdata\eng.traineddata
; runtime\ocr\tessdata\chi_sim.traineddata
; runtime\ocr\tessdata\chi_tra.traineddata
; runtime\ocr\tessdata\jpn.traineddata
; runtime\ocr\tessdata\kor.traineddata
; runtime\ocr\licenses\bzip2.txt
; runtime\ocr\licenses\curl.txt
; runtime\ocr\licenses\giflib.txt
; runtime\ocr\licenses\leptonica.txt
; runtime\ocr\licenses\libarchive.txt
; runtime\ocr\licenses\libjpeg-turbo.txt
; runtime\ocr\licenses\liblzma.txt
; runtime\ocr\licenses\libpng.txt
; runtime\ocr\licenses\libwebp.txt
; runtime\ocr\licenses\lz4.txt
; runtime\ocr\licenses\openjpeg.txt
; runtime\ocr\licenses\openssl.txt
; runtime\ocr\licenses\tiff.txt
; runtime\ocr\licenses\zlib.txt
; runtime\ocr\licenses\zstd.txt
; licenses\LICENSE-GPL-3.0-or-later.txt
; licenses\LICENSE-qwen-asr-MIT.txt
; licenses\LICENSE-LGPL-2.1-only.txt
; licenses\LICENSE-Unicode-3.0.txt
; licenses\THIRD-PARTY-NOTICES.md
; Screenshot capture libraries remain separate replaceable DLLs under LGPL-2.1-only.

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
  deleteuserdata.Height := ScaleY(24);
  deleteuserdata.Caption := 'Also permanently delete all VoxFlow user data';
  deleteuserdata.Checked := False;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and deleteuserdata.Checked then
  begin
    if MsgBox(
      'This permanently deletes settings, history, logs, and downloaded models from %LOCALAPPDATA%\VoxFlow. Continue?',
      mbConfirmation,
      MB_YESNO) <> IDYES then
      deleteuserdata.Checked := False;
  end;

  if (CurUninstallStep = usPostUninstall) and deleteuserdata.Checked then
    DelTree(ExpandConstant('{localappdata}\VoxFlow'), True, True, True);
end;
