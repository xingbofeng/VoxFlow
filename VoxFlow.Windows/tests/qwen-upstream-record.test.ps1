$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool] $Condition,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$windowsRoot = Split-Path -Parent $PSScriptRoot
$nativeRoot = Join-Path $windowsRoot 'native/qwen-asr'
$upstreamRecordPath = Join-Path $nativeRoot 'UPSTREAM.md'
$licensePath = Join-Path $nativeRoot 'LICENSE.upstream'
$manifestPath = Join-Path $nativeRoot 'MODEL_PROVENANCE.json'
$expectedRuntimeRevision = 'b00b789b17051aea61e9717458171100662318a4'

$upstreamRecord = Get-Content -LiteralPath $upstreamRecordPath -Raw
Assert-True ($upstreamRecord -notmatch '\bTODO\b') 'UPSTREAM.md must not contain unresolved TODO fields.'
Assert-True ($upstreamRecord.Contains($expectedRuntimeRevision)) 'UPSTREAM.md must pin the audited qwen-asr revision.'
Assert-True ($upstreamRecord.Contains('imports only `KERNEL32.dll`')) 'UPSTREAM.md must preserve the passing dependency-audit result.'
Assert-True ($upstreamRecord -notmatch '\bBLOCKED\b') 'UPSTREAM.md must not retain the superseded failed-spike status.'

Assert-True (Test-Path -LiteralPath $licensePath -PathType Leaf) 'The pinned upstream MIT license must be preserved.'
$licenseHash = (Get-FileHash -LiteralPath $licensePath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-True ($licenseHash -eq '663e51edcd9a3a8f858018ce6924ad2895a24c269c26c39ad75325bcd0f7e5bc') 'The preserved MIT license does not match the pinned upstream revision.'

Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'The raw Windows model provenance file is missing.'
$manifestText = Get-Content -LiteralPath $manifestPath -Raw
Assert-True ($manifestText -notmatch '(?i)mlx') 'Windows model provenance must not reuse an MLX source or artifact.'
$manifest = $manifestText | ConvertFrom-Json

Assert-True ($manifest.schemaVersion -eq 1) 'Unexpected model provenance schema version.'
Assert-True ($manifest.publishable -eq $true) 'The verified Windows runtime and model catalog must be publishable.'
Assert-True ($null -eq $manifest.publicationBlocker) 'A verified publishable runtime must not retain a publication blocker.'
Assert-True ($manifest.runtime.upstreamRevision -eq $expectedRuntimeRevision) 'Model provenance and runtime revision must agree.'
Assert-True ([Int64] $manifest.runtime.sourceArchive.bytes -eq 15567284) 'Pinned source archive byte count has drifted.'
Assert-True ($manifest.runtime.sourceArchive.sha256 -eq '00dca18f0a1b251635c8f712836f641f4b0304cb6eb4859456911b707f38ea0b') 'Pinned source archive SHA-256 has drifted.'
$validation = $manifest.runtime.windowsValidation
Assert-True ($validation.status -eq 'passed') 'Windows runtime validation must preserve the passing spike result.'
Assert-True ($validation.exitCode -eq 0) 'The audited MSVC build must have exited successfully.'
Assert-True ($validation.executableProduced -eq $true) 'The audited MSVC build must produce an executable.'
Assert-True ($validation.peMachine -eq 'IMAGE_FILE_MACHINE_AMD64') 'The audited executable must be Windows x64.'
Assert-True ($validation.runtimeLibraryRequested -eq '/MT') 'The audited executable must request the static MSVC runtime.'
Assert-True ($validation.warningsAsErrors -eq $true) 'The audited build must retain warnings-as-errors.'
Assert-True ($validation.dependencyAudit.status -eq 'passed') 'The native dependency audit must remain passing.'
Assert-True ($validation.dependencyAudit.externalRuntimeRequired -eq $false) 'The native dependency audit must not require an external runtime.'
Assert-True ($validation.dependencyAudit.importedDlls.Count -eq 1) 'The audited executable must import exactly one Windows DLL.'
Assert-True ($validation.dependencyAudit.importedDlls[0] -eq 'KERNEL32.dll') 'The audited executable must import only KERNEL32.dll.'
Assert-True ($validation.fixedWavExecuted -eq $true) 'The manifest must preserve the successful fixed-WAV run.'
$patchPath = Join-Path $nativeRoot $validation.portabilityOverlay.cleanupPatch
Assert-True (Test-Path -LiteralPath $patchPath -PathType Leaf) 'The audited MSVC cleanup patch is missing.'
$patchHash = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-True ($patchHash -eq $validation.portabilityOverlay.cleanupPatchSha256) 'The audited MSVC cleanup patch has drifted.'
Assert-True (Test-Path -LiteralPath (Join-Path $nativeRoot 'windows-port/src/windows_compat.c') -PathType Leaf) 'The Win32 portability implementation is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $nativeRoot 'windows-port/tests/windows_compat_test.c') -PathType Leaf) 'The Win32 portability contract test is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $nativeRoot 'verify-upstream-msvc.ps1') -PathType Leaf) 'The reproducible MSVC build verifier is missing.'
Assert-True (Test-Path -LiteralPath (Join-Path $nativeRoot 'verify-fixed-wav.ps1') -PathType Leaf) 'The reproducible fixed-WAV verifier is missing.'
$fixedWavPath = [System.IO.Path]::GetFullPath((Join-Path $nativeRoot $manifest.runtime.windowsValidation.fixedWav.path))
Assert-True (Test-Path -LiteralPath $fixedWavPath -PathType Leaf) 'The fixed-WAV evidence path does not resolve.'
Assert-True ((Get-Item -LiteralPath $fixedWavPath).Length -eq [Int64] $manifest.runtime.windowsValidation.fixedWav.bytes) 'The fixed-WAV byte count has drifted.'
$fixedWavHash = (Get-FileHash -LiteralPath $fixedWavPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-True ($fixedWavHash -eq $manifest.runtime.windowsValidation.fixedWav.sha256) 'The fixed-WAV SHA-256 has drifted.'
Assert-True ($validation.fixedWav.commandMode -eq '--stdin --stream') 'The fixed-WAV proof must exercise the streaming stdin path.'
Assert-True ($validation.fixedWav.exitCode -eq 0) 'The fixed-WAV process must exit successfully.'
Assert-True ([Int64] $validation.fixedWav.transcriptBytes -gt 0) 'The fixed-WAV proof must produce a non-empty transcript.'
Assert-True ($validation.fixedWav.transcriptSha256 -match '^[0-9a-f]{64}$') 'The fixed-WAV transcript evidence must include a SHA-256.'

$expectedModels = @{
    'qwen3-asr-0.6b' = @{
        Revision = '5eb144179a02acc5e5ba31e748d22b0cf3e303b0'
        TotalBytes = [Int64] 1880546725
        FileCount = 5
        Files = @{
            'config.json' = @{ Bytes = [Int64] 6193; Sha256 = '76d3ae4601ce939830b2517f4a6cadb86cc51316c3900af6b020b051c21a478c' }
            'generation_config.json' = @{ Bytes = [Int64] 142; Sha256 = '1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c' }
            'model.safetensors' = @{ Bytes = [Int64] 1876091704; Sha256 = '79d6cbd4c98c7bbffe9db2edac07f56cd6637d0d5944b27f6c2b8353840323ea' }
            'vocab.json' = @{ Bytes = [Int64] 2776833; Sha256 = 'ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910' }
            'merges.txt' = @{ Bytes = [Int64] 1671853; Sha256 = '8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5' }
        }
    }
    'qwen3-asr-1.7b' = @{
        Revision = '7278e1e70fe206f11671096ffdd38061171dd6e5'
        TotalBytes = [Int64] 4703041355
        FileCount = 7
        Files = @{
            'config.json' = @{ Bytes = [Int64] 6194; Sha256 = '2e74a751548b8ad7d7526d29365ad8144c345d8b412b1152d25dc6698452712f' }
            'generation_config.json' = @{ Bytes = [Int64] 142; Sha256 = '1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c' }
            'model.safetensors.index.json' = @{ Bytes = [Int64] 64821; Sha256 = 'f994739fe38e5210b9e3e8ce6c6307315e2ceac3cb630e7b7414d69dce520f60' }
            'model-00001-of-00002.safetensors' = @{ Bytes = [Int64] 4220320824; Sha256 = 'a4cd1f1a04d90b757dc7f7dd26254e69a013b19e80efe590a83c6a3bde8608d6' }
            'model-00002-of-00002.safetensors' = @{ Bytes = [Int64] 478200688; Sha256 = '6e0b9d9e09e2e0238e7ef3cc8a484ab387e91b90f1900bedf88bc92d7929ccfc' }
            'vocab.json' = @{ Bytes = [Int64] 2776833; Sha256 = 'ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910' }
            'merges.txt' = @{ Bytes = [Int64] 1671853; Sha256 = '8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5' }
        }
    }
}

Assert-True ($manifest.models.Count -eq $expectedModels.Count) 'Only the approved 0.6B and 1.7B raw model records are allowed.'
foreach ($model in $manifest.models) {
    Assert-True ($expectedModels.ContainsKey($model.id)) "Unexpected model id: $($model.id)"
    $expected = $expectedModels[$model.id]
    Assert-True ($model.repositoryRevision -eq $expected.Revision) "Unpinned model revision: $($model.id)"
    Assert-True ([Int64] $model.totalBytes -eq $expected.TotalBytes) "Incorrect total bytes: $($model.id)"
    Assert-True ($model.files.Count -eq $expected.FileCount) "Incorrect file count: $($model.id)"
    Assert-True ($model.license -eq 'Apache-2.0') "Incorrect model license: $($model.id)"

    $sum = [Int64] 0
    foreach ($file in $model.files) {
        Assert-True ($expected.Files.ContainsKey($file.name)) "Unexpected model file: $($model.id)/$($file.name)"
        $expectedFile = $expected.Files[$file.name]
        Assert-True ($file.url.StartsWith('https://huggingface.co/Qwen/')) "Non-official model URL: $($model.id)/$($file.name)"
        Assert-True ($file.url.Contains($model.repositoryRevision)) "Mutable model URL: $($model.id)/$($file.name)"
        Assert-True ($file.sha256 -match '^[0-9a-f]{64}$') "Invalid SHA-256: $($model.id)/$($file.name)"
        Assert-True ([Int64] $file.bytes -gt 0) "Invalid byte size: $($model.id)/$($file.name)"
        Assert-True ([Int64] $file.bytes -eq $expectedFile.Bytes) "Pinned byte count has drifted: $($model.id)/$($file.name)"
        Assert-True ($file.sha256 -eq $expectedFile.Sha256) "Pinned SHA-256 has drifted: $($model.id)/$($file.name)"
        $sum += [Int64] $file.bytes
    }
    Assert-True ($sum -eq [Int64] $model.totalBytes) "File sizes do not sum to totalBytes: $($model.id)"
}

Write-Output 'PASS: qwen-asr revision, license, Windows x64 runtime proof, fixed-WAV evidence, and raw model provenance are internally consistent.'
