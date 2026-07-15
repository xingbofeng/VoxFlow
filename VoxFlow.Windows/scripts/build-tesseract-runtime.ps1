[CmdletBinding()]
param(
    [string] $VcpkgRoot,
    [string] $InstallRoot,
    [string] $DownloadRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProcessHelpers.ps1')

$VcpkgBaseline = '03e366fb91e38b9432ebd5f8cc79f7c8f55e96ab'
$TessdataRevision = '87416418657359cb625c412a48b6e1d6d41c29bd'
$Triplet = 'x64-windows-static'
$OpenSslNasmPatchHash = '7dd0697985022e385f2c7d6e88709b4be891f8e69223fe96f6f283a03416c0f5'

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,
        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    Invoke-VoxFlowProcess -FilePath $FilePath -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory -Description $Description `
        -TimeoutSeconds 14400
}

function Invoke-Captured {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,
        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    return Invoke-VoxFlowProcess -FilePath $FilePath -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory -Description $Description `
        -TimeoutSeconds 1800 -CaptureOutput
}

function Add-WindowsSdkToolsToPath {
    $sdkBinRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
    $sdkToolRoots = @(Get-ChildItem -LiteralPath $sdkBinRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [Version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64' })
    $sdkTools = $sdkToolRoots | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_ 'rc.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_ 'mt.exe') -PathType Leaf)
    } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($sdkTools)) {
        throw 'The Windows 10/11 SDK x64 rc.exe and mt.exe tools are required.'
    }
    $pathEntries = @($env:PATH -split ';')
    if ($pathEntries -notcontains $sdkTools) {
        $env:PATH = "$sdkTools;$env:PATH"
    }
    $sdkVersionRoot = Split-Path -Parent $sdkTools
    $sdkVersion = Split-Path -Leaf $sdkVersionRoot
    $sdkRoot = Split-Path -Parent (Split-Path -Parent $sdkVersionRoot)
    $sdkLibraries = @(
        (Join-Path $sdkRoot "Lib/$sdkVersion/ucrt/x64"),
        (Join-Path $sdkRoot "Lib/$sdkVersion/um/x64")
    )
    $sdkIncludes = @(
        (Join-Path $sdkRoot "Include/$sdkVersion/ucrt"),
        (Join-Path $sdkRoot "Include/$sdkVersion/shared"),
        (Join-Path $sdkRoot "Include/$sdkVersion/um"),
        (Join-Path $sdkRoot "Include/$sdkVersion/winrt"),
        (Join-Path $sdkRoot "Include/$sdkVersion/cppwinrt")
    )
    if (-not (Test-Path -LiteralPath (Join-Path $sdkLibraries[1] 'kernel32.lib') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $sdkLibraries[0] 'ucrt.lib') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $sdkIncludes[2] 'windows.h') -PathType Leaf)) {
        throw "The selected Windows SDK $sdkVersion is incomplete."
    }
    $env:LIB = (@($env:LIB -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) + $sdkLibraries) -join ';'
    $env:INCLUDE = (@($env:INCLUDE -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) + $sdkIncludes) -join ';'
    $env:WindowsSdkDir = "$sdkRoot\"
    $env:WindowsSDKVersion = "$sdkVersion\"
    $env:UniversalCRTSdkDir = "$sdkRoot\"
    $env:UCRTVersion = $sdkVersion
    return $sdkTools
}

function Initialize-MsvcEnvironment {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installationPath = ''
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $installationPath = Invoke-Captured -FilePath $vswhere -WorkingDirectory $env:TEMP `
            -Description 'Locate Visual Studio C++ Build Tools' -Arguments @(
                '-latest', '-products', '*',
                '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
                '-property', 'installationPath'
            )
    }
    if ([string]::IsNullOrWhiteSpace($installationPath) -and
        (Test-Path -LiteralPath 'C:/BuildTools/Common7/Tools/VsDevCmd.bat' -PathType Leaf)) {
        $installationPath = 'C:/BuildTools'
    }
    $vsDevCmd = Join-Path $installationPath 'Common7/Tools/VsDevCmd.bat'
    if ([string]::IsNullOrWhiteSpace($installationPath) -or
        -not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) {
        throw 'Visual Studio C++ Build Tools with VsDevCmd.bat are required.'
    }

    $environmentBatch = Join-Path $env:TEMP ('voxflow-msvc-environment-' + [Guid]::NewGuid().ToString('N') + '.cmd')
    # VsDevCmd rewrites PATH and may drop PowerShell module discovery; keep PSModulePath
    # so later release-check child processes can still resolve Get-FileHash etc.
    $preservedPsModulePath = $env:PSModulePath
    try {
        @(
            '@echo off'
            "call `"$vsDevCmd`" -no_logo -arch=x64 -host_arch=x64"
            'if errorlevel 1 exit /b %errorlevel%'
            'set'
        ) | Set-Content -LiteralPath $environmentBatch -Encoding ASCII
        $environment = Invoke-Captured -FilePath 'cmd.exe' -WorkingDirectory $env:TEMP `
            -Description 'Initialize the Visual Studio x64 environment' -Arguments @(
                '/d', '/s', '/c', $environmentBatch
            )
        foreach ($line in $environment -split "`r?`n") {
            if ($line -match '^(?<name>[^=][^=]*)=(?<value>.*)$') {
                $name = $Matches.name
                if ($name -ieq 'PSModulePath') {
                    continue
                }
                [Environment]::SetEnvironmentVariable(
                    $name, $Matches.value, [EnvironmentVariableTarget]::Process)
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($preservedPsModulePath)) {
            $env:PSModulePath = $preservedPsModulePath
        }
        $system32 = Join-Path $env:SystemRoot 'System32'
        if (-not (($env:PATH -split ';') -contains $system32)) {
            $env:PATH = "$system32;$env:PATH"
        }
    }
    finally {
        Remove-Item -LiteralPath $environmentBatch -Force -ErrorAction SilentlyContinue
    }
}

function Install-PinnedNasm {
    param([Parameter(Mandatory = $true)][string] $ToolingRoot)

    $archive = Join-Path $ToolingRoot 'nasm-3.01-win64.zip'
    $archiveBytes = 594502
    $archiveHash = 'e0ba5157007abc7b1a65118a96657a961ddf55f7e3f632ee035366dfce039ca4'
    $nasmRoot = Join-Path $ToolingRoot 'nasm-3.01'
    $nasm = Join-Path $nasmRoot 'nasm.exe'
    New-Item -ItemType Directory -Path $ToolingRoot -Force | Out-Null
    $archiveValid = Test-Path -LiteralPath $archive -PathType Leaf
    if ($archiveValid) {
        $archiveValid = (Get-Item -LiteralPath $archive).Length -eq $archiveBytes -and
            (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -eq $archiveHash
    }
    if (-not $archiveValid) {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Invoke-WebRequest -UseBasicParsing `
            -Uri 'https://www.nasm.us/pub/nasm/releasebuilds/3.01/win64/nasm-3.01-win64.zip' `
            -OutFile $archive -TimeoutSec 600
    }
    if ((Get-Item -LiteralPath $archive).Length -ne $archiveBytes -or
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $archiveHash) {
        throw 'The pinned NASM 3.01 archive does not match the reviewed source.'
    }
    if (-not (Test-Path -LiteralPath $nasm -PathType Leaf) -or
        (Get-Item -LiteralPath $nasm).Length -ne 1955840 -or
        (Get-FileHash -LiteralPath $nasm -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '5f59c792cc3b92316a4e6d61cae192588a0d8f8fa30b33988a0f2230e5a9c22c') {
        Remove-Item -LiteralPath $nasmRoot -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -LiteralPath $archive -DestinationPath $ToolingRoot -Force
    }
    if (-not (Test-Path -LiteralPath $nasm -PathType Leaf) -or
        (Get-Item -LiteralPath $nasm).Length -ne 1955840 -or
        (Get-FileHash -LiteralPath $nasm -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            '5f59c792cc3b92316a4e6d61cae192588a0d8f8fa30b33988a0f2230e5a9c22c') {
        throw 'The extracted pinned NASM 3.01 executable is invalid.'
    }
    $env:PATH = "$nasmRoot;$env:PATH"
}

$windowsRoot = Split-Path -Parent $PSScriptRoot
$nativeBuildBase = if (-not [string]::IsNullOrWhiteSpace($env:VOXFLOW_NATIVE_BUILD_ROOT)) {
    $env:VOXFLOW_NATIVE_BUILD_ROOT
}
elseif (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    Join-Path $env:RUNNER_TEMP 'VoxFlowNative'
}
elseif (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Join-Path $env:LOCALAPPDATA 'VoxFlowBuild'
}
else {
    Join-Path $env:TEMP 'VoxFlowBuild'
}
if ([string]::IsNullOrWhiteSpace($VcpkgRoot)) {
    $VcpkgRoot = Join-Path $nativeBuildBase 'vcpkg'
}
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $nativeBuildBase 'installed'
}
if ([string]::IsNullOrWhiteSpace($DownloadRoot)) {
    $DownloadRoot = Join-Path $nativeBuildBase 'tessdata_fast'
}
$VcpkgRoot = [System.IO.Path]::GetFullPath($VcpkgRoot)
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$DownloadRoot = [System.IO.Path]::GetFullPath($DownloadRoot)
New-Item -ItemType Directory -Path (Split-Path -Parent $VcpkgRoot), $InstallRoot, $DownloadRoot -Force | Out-Null
Initialize-MsvcEnvironment
$sdkToolsPath = Add-WindowsSdkToolsToPath
Install-PinnedNasm -ToolingRoot (Join-Path $nativeBuildBase 'tooling')
$requiredToolCommands = @('cl.exe', 'link.exe', 'rc.exe', 'mt.exe', 'nasm.exe', 'cmd.exe')
foreach ($requiredToolCommand in $requiredToolCommands) {
    if ($null -eq (Get-Command $requiredToolCommand -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "The initialized MSVC environment is missing $requiredToolCommand."
    }
}
$systemCommandProcessor = Join-Path $env:SystemRoot 'System32/cmd.exe'
if (-not (Test-Path -LiteralPath $systemCommandProcessor -PathType Leaf)) {
    throw 'The initialized Windows build environment cannot locate System32\cmd.exe.'
}
$systemCommandProcessorCmakePath = $systemCommandProcessor.Replace('\', '/')
$env:VCPKG_ROOT = $VcpkgRoot
$env:VCPKG_KEEP_ENV_VARS = @(
    'PATH', 'INCLUDE', 'LIB', 'LIBPATH',
    'WindowsSdkDir', 'WindowsSDKVersion', 'UniversalCRTSdkDir', 'UCRTVersion'
) -join ';'
$overlayTriplets = Join-Path $nativeBuildBase 'triplets'
New-Item -ItemType Directory -Path $overlayTriplets -Force | Out-Null
$sdkToolsCmakePath = $sdkToolsPath.Replace('\', '/')
@(
    'set(VCPKG_TARGET_ARCHITECTURE x64)'
    'set(VCPKG_CRT_LINKAGE static)'
    'set(VCPKG_LIBRARY_LINKAGE static)'
    'set(VCPKG_BUILD_TYPE release)'
    'set(VCPKG_ENV_PASSTHROUGH PATH INCLUDE LIB LIBPATH WindowsSdkDir WindowsSDKVersion UniversalCRTSdkDir UCRTVersion)'
    "set(VCPKG_CMAKE_CONFIGURE_OPTIONS `"-DCMAKE_RC_COMPILER=$sdkToolsCmakePath/rc.exe`" `"-DCMAKE_MT=$sdkToolsCmakePath/mt.exe`")"
) | Set-Content -LiteralPath (Join-Path $overlayTriplets "$Triplet.cmake") -Encoding ASCII

$git = (Get-Command git.exe -ErrorAction Stop).Source
if (-not (Test-Path -LiteralPath (Join-Path $VcpkgRoot '.git') -PathType Container)) {
    Invoke-Checked -FilePath $git -WorkingDirectory (Split-Path -Parent $VcpkgRoot) `
        -Description 'Clone pinned vcpkg source' -Arguments @(
            'clone', '--filter=blob:none', '--no-checkout',
            'https://github.com/microsoft/vcpkg.git', $VcpkgRoot
        )
}
Invoke-Checked -FilePath $git -WorkingDirectory $VcpkgRoot `
    -Description 'Fetch pinned vcpkg baseline' -Arguments @(
        '-C', $VcpkgRoot, 'fetch', '--depth', '1', 'origin', $VcpkgBaseline
    )
Invoke-Checked -FilePath $git -WorkingDirectory $VcpkgRoot `
    -Description 'Select pinned vcpkg baseline' -Arguments @(
        '-C', $VcpkgRoot, 'switch', '--detach', 'FETCH_HEAD'
    )
$resolvedBaseline = Invoke-Captured -FilePath $git -WorkingDirectory $VcpkgRoot `
    -Description 'Verify pinned vcpkg baseline' -Arguments @(
        '-C', $VcpkgRoot, 'rev-parse', 'HEAD'
    )
$vcpkgTrackedStatus = Invoke-Captured -FilePath $git -WorkingDirectory $VcpkgRoot `
    -Description 'Verify pinned vcpkg source cleanliness' -Arguments @(
        '-C', $VcpkgRoot, 'status', '--porcelain', '--untracked-files=no', '--'
    )
if ($resolvedBaseline -ne $VcpkgBaseline -or
    -not [string]::IsNullOrWhiteSpace($vcpkgTrackedStatus)) {
    throw 'The vcpkg checkout does not match the clean reviewed baseline.'
}

# The pinned vcpkg OpenSSL port discovers NASM correctly but its probe does not
# survive into every Configure subprocess. Apply one reviewed source patch in a
# deterministic overlay and pass the acquired NASM executable explicitly.
$overlayPorts = Join-Path $nativeBuildBase 'overlay-ports'
$opensslOverlay = Join-Path $overlayPorts 'openssl'
Remove-Item -LiteralPath $opensslOverlay -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $overlayPorts -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $VcpkgRoot 'ports/openssl') `
    -Destination $opensslOverlay -Recurse -Force
$nasmProbePatch = Join-Path $PSScriptRoot 'patches/openssl-nasm-env.patch'
if ((Get-FileHash -LiteralPath $nasmProbePatch -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    $OpenSslNasmPatchHash) {
    throw 'The reviewed OpenSSL NASM environment patch changed.'
}
Copy-Item -LiteralPath $nasmProbePatch `
    -Destination (Join-Path $opensslOverlay 'voxflow-nasm-env.patch') -Force
$opensslMainPortfile = Join-Path $opensslOverlay 'portfile.cmake'
$opensslMainPortSource = Get-Content -LiteralPath $opensslMainPortfile -Raw
$patchListNeedle = '        cmake-config.patch'
if (-not $opensslMainPortSource.Contains($patchListNeedle) -or
    $opensslMainPortSource.IndexOf($patchListNeedle) -ne
        $opensslMainPortSource.LastIndexOf($patchListNeedle)) {
    throw 'The pinned OpenSSL patch inventory changed unexpectedly.'
}
$opensslMainPortSource = $opensslMainPortSource.Replace(
    $patchListNeedle,
    "        voxflow-nasm-env.patch$([Environment]::NewLine)$patchListNeedle")
$opensslMainPortSource | Set-Content -LiteralPath $opensslMainPortfile -Encoding UTF8
$opensslPortfile = Join-Path $opensslOverlay 'windows/portfile.cmake'
$opensslPortSource = Get-Content -LiteralPath $opensslPortfile -Raw
$nasmPathNeedle = '    vcpkg_add_to_path("${nasm_path}") # Needed by Configure'
$nasmPathReplacement = @'
    vcpkg_add_to_path("${nasm_path}") # Needed by Configure
'@.TrimEnd()
$releaseConfigureNeedle = '    PRERUN_SHELL_RELEASE "${PERL}" Configure'
$debugConfigureNeedle = '    PRERUN_SHELL_DEBUG "${PERL}" Configure'
$releaseConfigureReplacement = "    PRERUN_SHELL_RELEASE `"`${CMAKE_COMMAND}`" -E env `"VOXFLOW_OPENSSL_NASM=`${NASM}`" `"VOXFLOW_OPENSSL_CMD=$systemCommandProcessorCmakePath`" `"`${PERL}`" Configure"
$debugConfigureReplacement = "    PRERUN_SHELL_DEBUG `"`${CMAKE_COMMAND}`" -E env `"VOXFLOW_OPENSSL_NASM=`${NASM}`" `"VOXFLOW_OPENSSL_CMD=$systemCommandProcessorCmakePath`" `"`${PERL}`" Configure"
if (-not $opensslPortSource.Contains($nasmPathNeedle) -or
    -not $opensslPortSource.Contains($releaseConfigureNeedle) -or
    -not $opensslPortSource.Contains($debugConfigureNeedle)) {
    throw 'The pinned OpenSSL port no longer matches the reviewed NASM probe patch.'
}
# CI runners can enter the OpenSSL port with a sanitized PATH where bare
# `cmd` is not discoverable. Pin System32\cmd.exe for the portfile probe.
if ($opensslPortSource -notmatch 'find_program\s*\(\s*CMD_EXECUTABLE') {
    throw 'The pinned OpenSSL Windows port no longer probes for cmd.exe.'
}
$opensslPortSource = [regex]::Replace(
    $opensslPortSource,
    'find_program\s*\(\s*CMD_EXECUTABLE[^)]*\)',
    "set(CMD_EXECUTABLE `"$systemCommandProcessorCmakePath`")",
    1)
$opensslPortSource = $opensslPortSource.Replace($nasmPathNeedle, $nasmPathReplacement)
$opensslPortSource = $opensslPortSource.Replace($releaseConfigureNeedle, $releaseConfigureReplacement)
$opensslPortSource = $opensslPortSource.Replace($debugConfigureNeedle, $debugConfigureReplacement)
$opensslPortSource | Set-Content -LiteralPath $opensslPortfile -Encoding UTF8

$vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
if (-not (Test-Path -LiteralPath $vcpkg -PathType Leaf)) {
    $bootstrap = Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat'
    Invoke-Checked -FilePath 'cmd.exe' -WorkingDirectory $VcpkgRoot `
        -Description 'Bootstrap pinned vcpkg' -Arguments @(
            '/d', '/c', 'call', $bootstrap, '-disableMetrics'
        )
}
Invoke-Checked -FilePath $vcpkg -WorkingDirectory $VcpkgRoot `
    -Description 'Build pinned static Tesseract runtime' -Arguments @(
        'install', "tesseract:$Triplet", "--x-install-root=$InstallRoot",
        "--overlay-triplets=$overlayTriplets",
        "--overlay-ports=$overlayPorts",
        '--clean-after-build', '--disable-metrics'
    )

$models = [ordered]@{
    eng = @{ bytes = 4113088; sha256 = '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2' }
    chi_sim = @{ bytes = 2469156; sha256 = 'a5fcb6f0db1e1d6d8522f39db4e848f05984669172e584e8d76b6b3141e1f730' }
    chi_tra = @{ bytes = 2366642; sha256 = '529c5b5797d64b126065cd55f2bb4c7fd7b15790798091b1ff259941a829330b' }
    jpn = @{ bytes = 2471260; sha256 = '1f5de9236d2e85f5fdf4b3c500f2d4926f8d9449f28f5394472d9e8d83b91b4d' }
    kor = @{ bytes = 1677415; sha256 = '6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2' }
}
foreach ($language in $models.Keys) {
    $path = Join-Path $DownloadRoot "$language.traineddata"
    $expected = $models[$language]
    $valid = Test-Path -LiteralPath $path -PathType Leaf
    if ($valid) {
        $file = Get-Item -LiteralPath $path
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $valid = $file.Length -eq $expected.bytes -and $hash -eq $expected.sha256
    }
    if (-not $valid) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        $uri = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/$TessdataRevision/$language.traineddata"
        Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $path -TimeoutSec 600
    }
}

$packageRoot = Join-Path $InstallRoot $Triplet
$tesseract = Join-Path $packageRoot 'tools/tesseract/tesseract.exe'
$license = Join-Path $packageRoot 'share/tesseract/copyright'
& (Join-Path $windowsRoot 'scripts/stage-tesseract-runtime.ps1') `
    -TesseractExecutable $tesseract `
    -TessdataRoot $DownloadRoot `
    -LicensePath $license `
    -NativeLicenseRoot (Join-Path $packageRoot 'share')
Write-Output "PASS: built and staged Tesseract 5.5.2 from vcpkg $VcpkgBaseline ($Triplet)."
