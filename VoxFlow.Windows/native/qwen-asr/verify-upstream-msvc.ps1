[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SourceRoot,

    [Parameter(Mandatory = $true)]
    [string] $OutputRoot,

    [string] $ExpectedRevision = 'b00b789b17051aea61e9717458171100662318a4'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail {
    param([string] $Message)
    Write-Error $Message
    exit 1
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [string[]] $Arguments = @()
    )

    $captureId = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $env:TEMP "voxflow-qwen-$captureId.stdout"
    $stderrPath = Join-Path $env:TEMP "voxflow-qwen-$captureId.stderr"
    try {
        $startParameters = @{
            FilePath = $FilePath
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError = $stderrPath
            NoNewWindow = $true
            Wait = $true
            PassThru = $true
        }
        if ($Arguments.Count -gt 0) {
            $startParameters.ArgumentList = $Arguments
        }
        $process = Start-Process @startParameters
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath } else { @() }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath } else { @() }
        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            StdOut = @($stdout)
            StdErr = @($stderr)
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

$sourcePath = (Resolve-Path -LiteralPath $SourceRoot).Path
$outputPath = [System.IO.Path]::GetFullPath($OutputRoot)

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $git) {
    Fail 'git.exe is required to prove the upstream revision before compiling.'
}

$gitPath = $git.Source
$revisionProcess = Invoke-CapturedProcess -FilePath $gitPath -Arguments @('-C', "`"$sourcePath`"", 'rev-parse', 'HEAD')
$actualRevision = ($revisionProcess.StdOut -join '').Trim()
if ($revisionProcess.ExitCode -ne 0 -or $actualRevision -ne $ExpectedRevision) {
    Fail "SourceRoot must be a clean checkout at $ExpectedRevision; actual revision was '$actualRevision'."
}

$dirtyProcess = Invoke-CapturedProcess -FilePath $gitPath -Arguments @('-C', "`"$sourcePath`"", 'status', '--porcelain', '--untracked-files=no')
if ($dirtyProcess.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace(($dirtyProcess.StdOut -join ''))) {
    Fail 'SourceRoot must contain no tracked-file modifications.'
}

$sources = @(
    'main.c',
    'qwen_asr.c',
    'qwen_asr_kernels.c',
    'qwen_asr_kernels_generic.c',
    'qwen_asr_kernels_neon.c',
    'qwen_asr_kernels_avx.c',
    'qwen_asr_audio.c',
    'qwen_asr_encoder.c',
    'qwen_asr_decoder.c',
    'qwen_asr_tokenizer.c',
    'qwen_asr_safetensors.c'
)
foreach ($source in $sources) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourcePath $source) -PathType Leaf)) {
        Fail "Pinned source file is missing: $source"
    }
}

$portRoot = Join-Path $PSScriptRoot 'windows-port'
$portIncludePath = Join-Path $portRoot 'include'
$portSourcePath = Join-Path $portRoot 'src\windows_compat.c'
$portTestPath = Join-Path $portRoot 'tests\windows_compat_test.c'
$portPatchPath = Join-Path $portRoot 'patches\0001-msvc-c11-cleanups.patch'
foreach ($portInput in @($portIncludePath, $portSourcePath, $portTestPath, $portPatchPath)) {
    if (-not (Test-Path -LiteralPath $portInput)) {
        Fail "Windows portability input is missing: $portInput"
    }
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    Fail 'vswhere.exe was not found; a clean Visual Studio Build Tools installation is required.'
}

$installationProcess = Invoke-CapturedProcess -FilePath $vswhere -Arguments @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')
if ($installationProcess.ExitCode -ne 0 -or $installationProcess.StdOut.Count -eq 0) {
    $installationProcess = Invoke-CapturedProcess -FilePath $vswhere -Arguments @('-latest', '-products', '*', '-property', 'installationPath')
}
$installationPath = ($installationProcess.StdOut -join '').Trim()
if ([string]::IsNullOrWhiteSpace($installationPath)) {
    Fail 'The x64 MSVC toolset is not installed.'
}

$vcvars64 = Join-Path $installationPath 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path -LiteralPath $vcvars64 -PathType Leaf)) {
    Fail 'vcvars64.bat was not found in the selected MSVC installation.'
}

if (Test-Path -LiteralPath $outputPath) {
    if ($null -ne (Get-ChildItem -LiteralPath $outputPath -Force | Select-Object -First 1)) {
        Fail 'OutputRoot must be empty so stale objects cannot satisfy the spike.'
    }
} else {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

$sourceArchivePath = Join-Path $outputPath 'pinned-upstream.zip'
$patchedSourcePath = Join-Path $outputPath 'patched-upstream'
$archiveProcess = Invoke-CapturedProcess -FilePath $gitPath -Arguments @(
    '-C',
    "`"$sourcePath`"",
    'archive',
    '--format=zip',
    "--output=`"$sourceArchivePath`"",
    $ExpectedRevision
)
if ($archiveProcess.ExitCode -ne 0) {
    Fail "Failed to materialize the pinned upstream revision: $($archiveProcess.StdErr -join ' ')"
}
Expand-Archive -LiteralPath $sourceArchivePath -DestinationPath $patchedSourcePath

$patchCheck = Invoke-CapturedProcess -FilePath $gitPath -Arguments @(
    '-C',
    "`"$patchedSourcePath`"",
    'apply',
    '--check',
    "`"$portPatchPath`""
)
if ($patchCheck.ExitCode -ne 0) {
    Fail "The audited MSVC cleanup patch no longer applies: $($patchCheck.StdErr -join ' ')"
}
$patchApply = Invoke-CapturedProcess -FilePath $gitPath -Arguments @(
    '-C',
    "`"$patchedSourcePath`"",
    'apply',
    "`"$portPatchPath`""
)
if ($patchApply.ExitCode -ne 0) {
    Fail "Failed to apply the audited MSVC cleanup patch: $($patchApply.StdErr -join ' ')"
}

$executable = Join-Path $outputPath 'qwen_asr.exe'
$responseFile = Join-Path $outputPath 'qwen-asr-msvc.rsp'
$buildCommandFile = Join-Path $outputPath 'build-qwen-asr.cmd'
$buildLog = Join-Path $outputPath 'msvc-build.log'
$compatExecutable = Join-Path $outputPath 'windows_compat_test.exe'
$compatResponseFile = Join-Path $outputPath 'windows-compat-msvc.rsp'
$compatCommandFile = Join-Path $outputPath 'build-windows-compat.cmd'
$compatBuildLog = Join-Path $outputPath 'windows-compat-build.log'

$compatResponse = @(
    '/nologo',
    '/utf-8',
    '/std:c11',
    '/O2',
    '/W4',
    '/WX',
    '/MT',
    "/I`"$portIncludePath`"",
    '/FIwindows-msvc.h',
    "/Fe:`"$compatExecutable`"",
    "`"$portTestPath`"",
    "`"$portSourcePath`"",
    '/link /INCREMENTAL:NO'
)
$compatResponse | Set-Content -LiteralPath $compatResponseFile -Encoding Ascii
@(
    '@echo off',
    "call `"$vcvars64`" >nul",
    'if errorlevel 1 exit /b %errorlevel%',
    "cd /d `"$outputPath`"",
    "cl.exe @`"$compatResponseFile`" > `"$compatBuildLog`" 2>&1",
    'exit /b %errorlevel%'
) | Set-Content -LiteralPath $compatCommandFile -Encoding Ascii

# Do not use Start-Process file redirection around vcvars64.bat. Some clean
# Build Tools installations omit Windows SDK INCLUDE/LIB entries when the
# developer prompt itself receives file-backed standard handles. The command
# file redirects only cl.exe after vcvars has initialized the environment.
& $env:ComSpec /d /c "`"$compatCommandFile`""
$compatBuildExitCode = $LASTEXITCODE
if ($compatBuildExitCode -ne 0 -or -not (Test-Path -LiteralPath $compatExecutable -PathType Leaf)) {
    Write-Error "BLOCKED: Win32 portability contracts did not compile (MSVC exit $compatBuildExitCode). See $compatBuildLog"
    exit 1
}
$compatRun = Invoke-CapturedProcess -FilePath $compatExecutable
if ($compatRun.ExitCode -ne 0 -or ($compatRun.StdOut -join "`n") -notmatch 'PASS: Win32 qwen-asr portability contracts') {
    Write-Error "BLOCKED: Win32 portability contracts failed at runtime (exit $($compatRun.ExitCode))."
    exit 1
}

# /MT statically links the MSVC runtime. The dependency audit below rejects a
# packaged executable that still imports VC runtime, Python, CUDA, MLX, or a
# pthread compatibility DLL.
# Source: https://learn.microsoft.com/en-us/cpp/build/reference/md-mt-ld-use-run-time-library
$response = @(
    '/nologo',
    '/utf-8',
    '/std:c11',
    '/O2',
    '/fp:fast',
    '/arch:AVX2',
    '/W4',
    '/WX',
    '/MT',
    '/D_CRT_SECURE_NO_WARNINGS',
    '/D__AVX2__=1',
    '/D__FMA__=1',
    "/I`"$portIncludePath`"",
    "/I`"$patchedSourcePath`"",
    '/FIwindows-msvc.h',
    "/Fe:`"$executable`""
)
$response += $sources | ForEach-Object { "`"$(Join-Path $patchedSourcePath $_)`"" }
$response += "`"$portSourcePath`""
$response += '/link /INCREMENTAL:NO'
$response | Set-Content -LiteralPath $responseFile -Encoding Ascii

$command = @(
    '@echo off',
    "call `"$vcvars64`" >nul",
    'if errorlevel 1 exit /b %errorlevel%',
    "cd /d `"$outputPath`"",
    "cl.exe @`"$responseFile`" > `"$buildLog`" 2>&1",
    'exit /b %errorlevel%'
)
$command | Set-Content -LiteralPath $buildCommandFile -Encoding Ascii

& $env:ComSpec /d /c "`"$buildCommandFile`""
$buildExitCode = $LASTEXITCODE
$buildOutput = if (Test-Path -LiteralPath $buildLog) {
    @(Get-Content -LiteralPath $buildLog)
} else {
    @()
}
$buildOutput | ForEach-Object { Write-Output $_ }

if ($buildExitCode -ne 0 -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    Write-Error "BLOCKED: pinned upstream did not produce a Windows x64 executable (MSVC exit $buildExitCode). See $buildLog"
    exit $(if ($buildExitCode -eq 0) { 1 } else { $buildExitCode })
}

# IMAGE_FILE_MACHINE_AMD64 is 0x8664 in the PE/COFF file header.
# Source: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#machine-types
$stream = [System.IO.File]::OpenRead($executable)
try {
    $reader = [System.IO.BinaryReader]::new($stream)
    if ($reader.ReadUInt16() -ne 0x5A4D) {
        Fail 'The compiler output is not a PE executable.'
    }
    $stream.Position = 0x3C
    $peOffset = $reader.ReadUInt32()
    $stream.Position = $peOffset
    if ($reader.ReadUInt32() -ne 0x00004550) {
        Fail 'The compiler output has no PE signature.'
    }
    if ($reader.ReadUInt16() -ne 0x8664) {
        Fail 'The compiler output is not Windows x64.'
    }
}
finally {
    $stream.Dispose()
}

$dependencyCommandFile = Join-Path $outputPath 'inspect-qwen-asr.cmd'
$dependencyLog = Join-Path $outputPath 'dumpbin-dependents.log'
@(
    '@echo off',
    "call `"$vcvars64`" >nul",
    'if errorlevel 1 exit /b %errorlevel%',
    "dumpbin.exe /nologo /dependents `"$executable`" > `"$dependencyLog`" 2>&1",
    'exit /b %errorlevel%'
) | Set-Content -LiteralPath $dependencyCommandFile -Encoding Ascii

# /DEPENDENTS lists the DLLs imported by an image.
# Source: https://learn.microsoft.com/en-us/cpp/build/reference/dependents
& $env:ComSpec /d /c "`"$dependencyCommandFile`""
$dependencyExitCode = $LASTEXITCODE
$dependencyOutput = if (Test-Path -LiteralPath $dependencyLog) {
    @(Get-Content -LiteralPath $dependencyLog)
} else {
    @()
}
if ($dependencyExitCode -ne 0) {
    Fail "dumpbin dependency inspection failed with exit code $dependencyExitCode."
}

$dependencyText = $dependencyOutput -join "`n"
$forbiddenImports = @(
    '(?i)python[^\s]*\.dll',
    '(?i)cudart[^\s]*\.dll',
    '(?i)nvcuda\.dll',
    '(?i)mlx[^\s]*\.dll',
    '(?i)libwinpthread[^\s]*\.dll',
    '(?i)vcruntime[^\s]*\.dll',
    '(?i)msvcp[^\s]*\.dll'
)
foreach ($pattern in $forbiddenImports) {
    if ($dependencyText -match $pattern) {
        Fail "Forbidden runtime dependency matched '$pattern'. See $dependencyLog"
    }
}

Write-Output "PASS: $ExpectedRevision plus the audited Win32 overlay built as Windows x64 with /MT and passed the native dependency audit."
