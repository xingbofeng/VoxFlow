Set-StrictMode -Version Latest

$script:VoxFlowQwenRuntimeId = 'qwen-asr-native-bridge'
$script:VoxFlowQwenRepository = 'https://github.com/antirez/qwen-asr'
$script:VoxFlowQwenRevision = 'b00b789b17051aea61e9717458171100662318a4'
$script:VoxFlowQwenPatchPath = 'native/qwen-asr/windows-port/patches/0001-msvc-c11-cleanups.patch'
$script:VoxFlowQwenPatchHash = '519fd8434a4e5f9ffd4a067686c552905eca0a5e1387ac2f467ea9007f2965a8'
$script:VoxFlowQwenWindowsRoot = Split-Path -Parent $PSScriptRoot
$script:VoxFlowQwenRepositoryRoot = Split-Path -Parent $script:VoxFlowQwenWindowsRoot
$script:VoxFlowQwenBridgeRepository = 'https://github.com/xingbofeng/VoxFlow'
$script:VoxFlowQwenBridgeSourcePaths = @(
    'native/qwen-asr-bridge/CMakeLists.txt',
    'native/qwen-asr-bridge/include/vf_qwen_bridge.h',
    'native/qwen-asr-bridge/src/vf_qwen_bridge.cpp',
    'native/qwen-asr/windows-port/include/dirent.h',
    'native/qwen-asr/windows-port/include/pthread.h',
    'native/qwen-asr/windows-port/include/sys/mman.h',
    'native/qwen-asr/windows-port/include/sys/time.h',
    'native/qwen-asr/windows-port/include/unistd.h',
    'native/qwen-asr/windows-port/include/windows-msvc.h',
    'native/qwen-asr/windows-port/src/windows_compat.c'
)

function Get-VoxFlowQwenBridgeRepositoryState {
    $revision = ''
    $sourceStatus = ''
    $useWslGit = $false
    $gitMetadata = Join-Path $script:VoxFlowQwenRepositoryRoot '.git'
    if (Test-Path -LiteralPath $gitMetadata -PathType Leaf) {
        $gitPointer = Get-Content -LiteralPath $gitMetadata -Raw
        $useWslGit = $gitPointer -match '(?m)^gitdir:\s*/'
    }
    if (-not $useWslGit) {
        try {
            $revision = Invoke-VoxFlowProcess -FilePath 'git.exe' -Arguments @(
                '-C', $script:VoxFlowQwenRepositoryRoot, 'rev-parse', 'HEAD'
            ) -WorkingDirectory $script:VoxFlowQwenRepositoryRoot `
                -Description 'Qwen bridge repository revision probe' -TimeoutSeconds 120 -CaptureOutput
            $sourceStatus = Invoke-VoxFlowProcess -FilePath 'git.exe' -Arguments @(
                '-C', $script:VoxFlowQwenRepositoryRoot, 'status', '--porcelain', '--untracked-files=all', '--',
                'VoxFlow.Windows/native/qwen-asr-bridge',
                'VoxFlow.Windows/native/qwen-asr/windows-port'
            ) -WorkingDirectory $script:VoxFlowQwenRepositoryRoot `
                -Description 'Qwen bridge repository cleanliness probe' -TimeoutSeconds 120 -CaptureOutput
        }
        catch {
            $useWslGit = $true
        }
    }
    if ($useWslGit) {
        $wslRepositoryRoot = Invoke-VoxFlowProcess -FilePath 'wsl.exe' -Arguments @(
            '--exec', 'wslpath', '-a', $script:VoxFlowQwenRepositoryRoot
        ) -WorkingDirectory $script:VoxFlowQwenRepositoryRoot `
            -Description 'Qwen bridge WSL repository path probe' -TimeoutSeconds 120 -CaptureOutput
        $revision = Invoke-VoxFlowProcess -FilePath 'wsl.exe' -Arguments @(
            '--exec', 'git', '-C', $wslRepositoryRoot, 'rev-parse', 'HEAD'
        ) -WorkingDirectory $script:VoxFlowQwenRepositoryRoot `
            -Description 'Qwen bridge WSL repository revision probe' -TimeoutSeconds 120 -CaptureOutput
        $sourceStatus = Invoke-VoxFlowProcess -FilePath 'wsl.exe' -Arguments @(
            '--exec', 'git', '-C', $wslRepositoryRoot, 'status', '--porcelain', '--untracked-files=all', '--',
            'VoxFlow.Windows/native/qwen-asr-bridge',
            'VoxFlow.Windows/native/qwen-asr/windows-port'
        ) -WorkingDirectory $script:VoxFlowQwenRepositoryRoot `
            -Description 'Qwen bridge WSL repository cleanliness probe' -TimeoutSeconds 120 -CaptureOutput
    }
    if ($revision -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'The Qwen bridge repository revision could not be resolved.'
    }
    return [PSCustomObject]@{
        Revision = $revision.ToLowerInvariant()
        Dirty = -not [string]::IsNullOrWhiteSpace($sourceStatus)
    }
}

function Get-VoxFlowQwenBridgeSourceInventory {
    return @($script:VoxFlowQwenBridgeSourcePaths | ForEach-Object {
        $relativePath = $_
        $sourcePath = Join-Path $script:VoxFlowQwenWindowsRoot $relativePath.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "The reviewed Qwen bridge source is missing: $relativePath"
        }
        [ordered]@{
            path = $relativePath
            sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}

function Assert-VoxFlowQwenX64Pe {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x100 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        throw 'The Qwen native bridge is not a PE image.'
    }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($peOffset -lt 0 -or ($peOffset + 6) -gt $bytes.Length -or
        [BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664) {
        throw 'The Qwen native bridge is not Windows x64.'
    }
}

function Assert-VoxFlowQwenNativeAbi {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not ('VoxFlow.Release.QwenNativeProbe' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace VoxFlow.Release
{
    public static class QwenNativeProbe
    {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int Int32ExportDelegate();

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryW(string path);

        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
        private static extern IntPtr GetProcAddress(IntPtr module, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FreeLibrary(IntPtr module);

        private static int ReadInt32Export(string path, string exportName)
        {
            IntPtr module = LoadLibraryW(path);
            if (module == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            try
            {
                IntPtr address = GetProcAddress(module, exportName);
                if (address == IntPtr.Zero)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                var export = (Int32ExportDelegate)Marshal.GetDelegateForFunctionPointer(
                    address,
                    typeof(Int32ExportDelegate));
                return export();
            }
            finally
            {
                FreeLibrary(module);
            }
        }

        public static int ReadAbiVersion(string path)
        {
            return ReadInt32Export(path, "vf_qwen_abi_version");
        }

        public static int ReadBackendKind(string path)
        {
            return ReadInt32Export(path, "vf_qwen_backend_kind");
        }
    }
}
'@
    }

    try {
        $abiVersion = [VoxFlow.Release.QwenNativeProbe]::ReadAbiVersion($Path)
    }
    catch {
        throw 'The Qwen production bridge could not be loaded for its ABI smoke check.'
    }
    if ($abiVersion -ne 1) {
        throw "The Qwen production bridge ABI version is unsupported: $abiVersion"
    }
    try {
        $backendKind = [VoxFlow.Release.QwenNativeProbe]::ReadBackendKind($Path)
    }
    catch {
        throw 'The Qwen production bridge does not expose its backend identity.'
    }
    if ($backendKind -ne 0) {
        throw 'The Qwen native bridge is not the production backend.'
    }
}

function Assert-VoxFlowQwenRuntimeManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $BinaryPath,

        [Parameter(Mandatory = $true)]
        [string] $ManifestPath,

        [switch] $AllowDirtySource
    )

    $binary = (Resolve-Path -LiteralPath $BinaryPath).Path
    $manifestFile = (Resolve-Path -LiteralPath $ManifestPath).Path
    if ([System.IO.Path]::GetFileName($binary) -ne 'qwen_asr.dll') {
        throw 'The Qwen native bridge binary must be named qwen_asr.dll.'
    }

    $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or
        $manifest.runtimeId -ne $script:VoxFlowQwenRuntimeId -or
        $manifest.binary -ne 'qwen_asr.dll' -or
        $manifest.architecture -ne 'x64' -or
        $manifest.license -ne 'MIT' -or
        [long]$manifest.size -le 0 -or
        $manifest.sha256 -notmatch '^[0-9a-f]{64}$' -or
        $manifest.source.repository -ne $script:VoxFlowQwenRepository -or
        $manifest.source.revision -ne $script:VoxFlowQwenRevision -or
        $manifest.source.patch.path -ne $script:VoxFlowQwenPatchPath -or
        $manifest.source.patch.sha256 -ne $script:VoxFlowQwenPatchHash -or
        $manifest.source.bridge.repository -ne $script:VoxFlowQwenBridgeRepository -or
        $manifest.source.bridge.revision -notmatch '^[0-9a-f]{40}$' -or
        $manifest.source.bridge.dirty -isnot [bool] -or
        ($manifest.source.bridge.dirty -and -not $AllowDirtySource) -or
        $manifest.build.configuration -ne 'Release' -or
        $manifest.build.target -ne 'qwen_asr' -or
        $manifest.build.backend -ne 'production' -or
        $manifest.build.testBackend -ne $false -or
        $manifest.build.crtLinkage -ne 'static' -or
        $manifest.build.warningsAsErrors -ne $true) {
        throw 'The Qwen native bridge manifest is invalid or does not describe the audited production build.'
    }

    $expectedBridgeFiles = @(Get-VoxFlowQwenBridgeSourceInventory)
    $manifestBridgeFiles = @($manifest.source.bridge.files)
    if ($manifestBridgeFiles.Count -ne $expectedBridgeFiles.Count) {
        throw 'The Qwen native bridge source inventory is incomplete.'
    }
    for ($index = 0; $index -lt $expectedBridgeFiles.Count; $index++) {
        if ($manifestBridgeFiles[$index].path -ne $expectedBridgeFiles[$index].path -or
            $manifestBridgeFiles[$index].sha256 -ne $expectedBridgeFiles[$index].sha256) {
            throw 'The Qwen native bridge source inventory does not match the reviewed checkout.'
        }
    }

    $repositoryState = Get-VoxFlowQwenBridgeRepositoryState
    if ($manifest.source.bridge.revision -ne $repositoryState.Revision -or
        $manifest.source.bridge.dirty -ne $repositoryState.Dirty -or
        ($repositoryState.Dirty -and -not $AllowDirtySource) -or
        ($env:GITHUB_SHA -match '^[0-9a-fA-F]{40}$' -and
            $env:GITHUB_SHA.ToLowerInvariant() -ne $repositoryState.Revision)) {
        throw 'The Qwen bridge manifest does not match the current checkout state.'
    }

    $item = Get-Item -LiteralPath $binary
    $hash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne [long]$manifest.size -or $hash -ne $manifest.sha256) {
        throw 'The Qwen native bridge does not match its audited manifest.'
    }
    Assert-VoxFlowQwenX64Pe -Path $binary
    Assert-VoxFlowQwenNativeAbi -Path $binary
    return $manifest
}

function New-VoxFlowQwenRuntimeManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $BinaryPath,

        [Parameter(Mandatory = $true)]
        [string] $ManifestPath,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{40}$')]
        [string] $SourceRevision,

        [bool] $SourceDirty = $false
    )

    $binary = (Resolve-Path -LiteralPath $BinaryPath).Path
    if ([System.IO.Path]::GetFileName($binary) -ne 'qwen_asr.dll') {
        throw 'The Qwen native bridge binary must be named qwen_asr.dll.'
    }
    Assert-VoxFlowQwenX64Pe -Path $binary
    Assert-VoxFlowQwenNativeAbi -Path $binary

    $item = Get-Item -LiteralPath $binary
    $hash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        schemaVersion = 1
        runtimeId = $script:VoxFlowQwenRuntimeId
        binary = 'qwen_asr.dll'
        architecture = 'x64'
        size = [long]$item.Length
        sha256 = $hash
        license = 'MIT'
        source = [ordered]@{
            repository = $script:VoxFlowQwenRepository
            revision = $script:VoxFlowQwenRevision
            patch = [ordered]@{
                path = $script:VoxFlowQwenPatchPath
                sha256 = $script:VoxFlowQwenPatchHash
            }
            bridge = [ordered]@{
                repository = $script:VoxFlowQwenBridgeRepository
                revision = $SourceRevision.ToLowerInvariant()
                dirty = $SourceDirty
                files = @(Get-VoxFlowQwenBridgeSourceInventory)
            }
        }
        build = [ordered]@{
            configuration = 'Release'
            target = 'qwen_asr'
            backend = 'production'
            testBackend = $false
            crtLinkage = 'static'
            warningsAsErrors = $true
        }
    }

    $destination = [System.IO.Path]::GetFullPath($ManifestPath)
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $destination -Encoding UTF8
    Assert-VoxFlowQwenRuntimeManifest -BinaryPath $binary -ManifestPath $destination `
        -AllowDirtySource:$SourceDirty | Out-Null
    return $destination
}
