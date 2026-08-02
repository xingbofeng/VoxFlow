[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $TesseractExecutable,

    [Parameter(Mandatory = $true)]
    [string] $TessdataRoot,

    [Parameter(Mandatory = $true)]
    [string] $LicensePath,

    [string] $NativeLicenseRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProcessHelpers.ps1')
$openSslNasmPatchHash = '7dd0697985022e385f2c7d6e88709b4be891f8e69223fe96f6f283a03416c0f5'

function Fail {
    param([string] $Message)
    throw $Message
}

function Assert-X64Pe {
    param([string] $Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x100 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        Fail "Tesseract is not a PE image: $Path"
    }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($peOffset -lt 0 -or ($peOffset + 6) -gt $bytes.Length -or
        [BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664) {
        Fail "Tesseract is not an x64 PE image: $Path"
    }
}

function Assert-FixedFile {
    param(
        [string] $Path,
        [long] $ExpectedBytes,
        [string] $ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "Required fixed OCR input is missing: $Path"
    }
    $file = Get-Item -LiteralPath $Path
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($file.Length -ne $ExpectedBytes -or $hash -ne $ExpectedSha256) {
        Fail "Fixed OCR input hash or size does not match the reviewed source: $Path"
    }
}

$models = [ordered]@{
    eng = @{ bytes = 4113088; sha256 = '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2' }
    chi_sim = @{ bytes = 2469156; sha256 = 'a5fcb6f0db1e1d6d8522f39db4e848f05984669172e584e8d76b6b3141e1f730' }
    chi_tra = @{ bytes = 2366642; sha256 = '529c5b5797d64b126065cd55f2bb4c7fd7b15790798091b1ff259941a829330b' }
    jpn = @{ bytes = 2471260; sha256 = '1f5de9236d2e85f5fdf4b3c500f2d4926f8d9449f28f5394472d9e8d83b91b4d' }
    kor = @{ bytes = 1677415; sha256 = '6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2' }
}
$nativeDependencies = @(
    [ordered]@{ port = 'bzip2'; version = '1.0.8#6'; license = 'bzip2-1.0.6'; source = 'https://sourceware.org/bzip2/'; bytes = 1896; sha256 = 'c6dbbf828498be844a89eaa3b84adbab3199e342eb5cb2ed2f0d4ba7ec0f38a3' }
    [ordered]@{ port = 'curl'; version = '8.21.0#1'; license = 'curl AND ISC AND BSD-3-Clause'; source = 'https://github.com/curl/curl'; bytes = 2055; sha256 = '543457a53893d439ac029f115c15940c0921ce1b919db501bbad266e2a4d1059' }
    [ordered]@{ port = 'giflib'; version = '6.1.3'; license = 'MIT'; source = 'https://sourceforge.net/projects/giflib/'; bytes = 1039; sha256 = 'ed5d90cb4a041bddad679470a071302ab05ae5d0ec2cf8f9c97ad7b2708751e6' }
    [ordered]@{ port = 'leptonica'; version = '1.87.0'; license = 'BSD-2-Clause'; source = 'https://github.com/DanBloomberg/leptonica'; bytes = 1521; sha256 = '87829abb5bbb00b55a107365da89e9a33f86c4250169e5a1e5588505be7d5806' }
    [ordered]@{ port = 'libarchive'; version = '3.8.7'; license = 'BSD-2-Clause'; source = 'https://github.com/libarchive/libarchive'; bytes = 3089; sha256 = '30e556b3959e3985d66efefec5eaac51d4995053caa1d3cffe6eb916f146f229' }
    [ordered]@{ port = 'libjpeg-turbo'; version = '3.2.0'; license = 'BSD-3-Clause AND IJG'; source = 'https://github.com/libjpeg-turbo/libjpeg-turbo'; bytes = 6077; sha256 = 'ba6bceebcba0fdd35488477c2cca8c4632ce82c74dbfbc87d886ce6fc4433579' }
    [ordered]@{ port = 'liblzma'; version = '5.8.3'; license = '0BSD'; source = 'https://github.com/tukaani-project/xz'; bytes = 3119; sha256 = '616a3ad264ce29b8f1cb97e53037b139d406899ca8d1f799651e17bfa09830b8' }
    [ordered]@{ port = 'libpng'; version = '1.6.58'; license = 'libpng-2.0'; source = 'https://github.com/pnggroup/libpng'; bytes = 5345; sha256 = 'bdb0a645ea18c60507d0368379b1ac5474b92255fcc2d115e07486a7672ba526' }
    [ordered]@{ port = 'libwebp'; version = '1.6.0#2'; license = 'BSD-3-Clause'; source = 'https://github.com/webmproject/libwebp'; bytes = 3017; sha256 = '050b5ba2c8eb0bd3b996e12ef79312a1c62237f2de1b3c609843f00bb74744f3' }
    [ordered]@{ port = 'lz4'; version = '1.10.0'; license = 'BSD-2-Clause'; source = 'https://github.com/lz4/lz4'; bytes = 1311; sha256 = '8b58c446121a109ccf32edc094bba3010a3d85e4ee3702950db55e4d3e87736c' }
    [ordered]@{ port = 'openjpeg'; version = '2.5.4'; license = 'BSD-2-Clause'; source = 'https://github.com/uclouvain/openjpeg'; bytes = 2112; sha256 = 'a6af136f3e15038a666b61f376612a07d9a4e48cb7c01adbf3e33b3f14ab49b6' }
    [ordered]@{ port = 'openssl'; version = '3.6.3'; license = 'Apache-2.0'; source = 'https://github.com/openssl/openssl'; bytes = 10175; sha256 = '7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a' }
    [ordered]@{ port = 'tiff'; version = '4.7.2'; license = 'libtiff'; source = 'https://gitlab.com/libtiff/libtiff'; bytes = 2416; sha256 = '0e27c2382d7b8147972bbb746e04059a1152c8d0fda9d03ef1399d1a433c4ade' }
    [ordered]@{ port = 'zlib'; version = '1.3.2#1'; license = 'Zlib'; source = 'https://github.com/madler/zlib'; bytes = 1002; sha256 = 'e32ff4e00d9d94930537635291da39e7e612703334bf6fde8c7f1686fe8a45a2' }
    [ordered]@{ port = 'zstd'; version = '1.5.7'; license = 'BSD-3-Clause'; source = 'https://github.com/facebook/zstd'; bytes = 20086; sha256 = '434dca949c6da7c500413aef694539fe37f867dd1a94d83d4ed1d260194e2660' }
)

$windowsRoot = Split-Path -Parent $PSScriptRoot
$openSslNasmPatch = Join-Path $PSScriptRoot 'patches/openssl-nasm-env.patch'
if (-not (Test-Path -LiteralPath $openSslNasmPatch -PathType Leaf) -or
    (Get-FileHash -LiteralPath $openSslNasmPatch -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        $openSslNasmPatchHash) {
    Fail 'The reviewed OpenSSL NASM environment patch is missing or changed.'
}
$runtimeRoot = Join-Path $windowsRoot 'runtime/ocr'
$tesseract = (Resolve-Path -LiteralPath $TesseractExecutable).Path
$sourceTessdata = (Resolve-Path -LiteralPath $TessdataRoot).Path
$license = (Resolve-Path -LiteralPath $LicensePath).Path
if ([string]::IsNullOrWhiteSpace($NativeLicenseRoot)) {
    $NativeLicenseRoot = Split-Path -Parent (Split-Path -Parent $license)
}
$nativeLicenseSource = (Resolve-Path -LiteralPath $NativeLicenseRoot).Path
if ([System.IO.Path]::GetFileName($tesseract) -ne 'tesseract.exe') {
    Fail 'TesseractExecutable must identify the controlled tesseract.exe output.'
}

Assert-X64Pe $tesseract
$version = Invoke-VoxFlowProcess -FilePath $tesseract -Arguments @('--version') `
    -WorkingDirectory (Split-Path -Parent $tesseract) `
    -Description 'Tesseract version probe' -TimeoutSeconds 60 -CaptureOutput
if ($version -notmatch '(?m)^tesseract 5\.5\.2\b') {
    Fail 'The controlled Tesseract executable must report version 5.5.2.'
}
Assert-FixedFile $license 11358 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30'
foreach ($language in $models.Keys) {
    $model = $models[$language]
    Assert-FixedFile (Join-Path $sourceTessdata "$language.traineddata") $model.bytes $model.sha256
}
foreach ($dependency in $nativeDependencies) {
    $dependencyLicense = Join-Path $nativeLicenseSource "$($dependency.port)/copyright"
    Assert-FixedFile $dependencyLicense $dependency.bytes $dependency.sha256
}

Remove-Item -LiteralPath $runtimeRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $runtimeRoot 'tessdata'), (Join-Path $runtimeRoot 'licenses') -Force | Out-Null
Copy-Item -LiteralPath $tesseract -Destination (Join-Path $runtimeRoot 'tesseract.exe') -Force
Copy-Item -LiteralPath $license -Destination (Join-Path $runtimeRoot 'LICENSE.txt') -Force
foreach ($language in $models.Keys) {
    Copy-Item -LiteralPath (Join-Path $sourceTessdata "$language.traineddata") `
        -Destination (Join-Path $runtimeRoot "tessdata/$language.traineddata") -Force
}
foreach ($dependency in $nativeDependencies) {
    Copy-Item -LiteralPath (Join-Path $nativeLicenseSource "$($dependency.port)/copyright") `
        -Destination (Join-Path $runtimeRoot "licenses/$($dependency.port).txt") -Force
}

$files = @('tesseract.exe', 'LICENSE.txt') + @(
    $models.Keys | ForEach-Object { "tessdata/$_.traineddata" }) + @(
    $nativeDependencies | ForEach-Object { "licenses/$($_.port).txt" })
$manifestFiles = @($files | ForEach-Object {
    $path = Join-Path $runtimeRoot $_.Replace('/', '\')
    $info = Get-Item -LiteralPath $path
    [ordered]@{
        path = $_
        size = [long]$info.Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$manifestLanguages = @($models.Keys | ForEach-Object {
    $model = $models[$_]
    [ordered]@{
        language = $_
        path = "tessdata/$_.traineddata"
        size = [long]$model.bytes
        sha256 = $model.sha256
    }
})
$manifest = [ordered]@{
    schemaVersion = 1
    runtimeId = 'tesseract-5.5.2-vcpkg-03e366fb-x64-static'
    version = '5.5.2'
    architecture = 'x64'
    binary = 'tesseract.exe'
    license = 'Apache-2.0'
    source = [ordered]@{
        repository = 'https://github.com/tesseract-ocr/tesseract'
        tag = '5.5.2'
    }
    build = [ordered]@{
        packageManager = 'vcpkg'
        baseline = '03e366fb91e38b9432ebd5f8cc79f7c8f55e96ab'
        triplet = 'x64-windows-static'
        buildType = 'release'
        nasm = '3.01'
        opensslNasmPatchSha256 = $openSslNasmPatchHash
    }
    tessdata = [ordered]@{
        repository = 'https://github.com/tesseract-ocr/tessdata_fast'
        revision = '87416418657359cb625c412a48b6e1d6d41c29bd'
        license = 'Apache-2.0'
    }
    nativeDependencies = @($nativeDependencies | ForEach-Object {
        [ordered]@{
            port = $_.port
            version = $_.version
            license = $_.license
            source = $_.source
            notice = "licenses/$($_.port).txt"
        }
    })
    files = $manifestFiles
    languages = $manifestLanguages
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content `
    -LiteralPath (Join-Path $runtimeRoot 'TESSERACT_RUNTIME_MANIFEST.json') -Encoding UTF8
Write-Output "PASS: staged controlled Tesseract runtime at $runtimeRoot"
