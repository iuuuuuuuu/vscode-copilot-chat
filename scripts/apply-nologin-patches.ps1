<#
.SYNOPSIS
    NoLogin 补丁自动应用脚本
.PARAMETER SkipBuild
    只应用补丁，不构建 VSIX
.PARAMETER SkipFetch
    不拉取上游，直接在当前代码上应用
#>
param(
    [switch]$SkipBuild,
    [switch]$SkipFetch
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $PSScriptRoot
$patchFile = Join-Path $rootDir "patches\nologin.patch"
$buildScript = Join-Path $rootDir "_build_nologin.js"

Set-Location $rootDir

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " NoLogin Patch Applier" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Check patch file
if (-not (Test-Path $patchFile)) {
    Write-Host "[ERROR] Patch file not found: $patchFile" -ForegroundColor Red
    exit 1
}

# 2. Fetch upstream
if (-not $SkipFetch) {
    Write-Host "[1/4] Fetching upstream..." -ForegroundColor Green
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git fetch upstream 2>$null
    if ($LASTEXITCODE -ne 0) {
        git fetch origin 2>$null
    }
    $ErrorActionPreference = $prevEAP
    Write-Host "  Done." -ForegroundColor Gray
} else {
    Write-Host "[1/4] Skipping fetch" -ForegroundColor Yellow
}

# 3. Stash (best-effort)
Write-Host "[2/4] Saving current state..." -ForegroundColor Green
$lockFile = Join-Path $rootDir ".git\index.lock"
if (Test-Path $lockFile) {
    Remove-Item -Force $lockFile -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
git stash push -m "nologin-pre-update" 2>$null
$ErrorActionPreference = $prevEAP
Write-Host "  Done." -ForegroundColor Gray

# 4. Apply patch
Write-Host "[3/4] Applying nologin.patch..." -ForegroundColor Green

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
git apply --check $patchFile 2>$null
$checkOk = $LASTEXITCODE -eq 0
$ErrorActionPreference = $prevEAP

if ($checkOk) {
    git apply $patchFile
    Write-Host "  Patch applied cleanly!" -ForegroundColor Green
} else {
    Write-Host "  Clean apply failed, trying 3-way merge..." -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git apply --3way $patchFile 2>$null
    $mergeOk = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $prevEAP

    if ($mergeOk) {
        Write-Host "  3-way merge applied!" -ForegroundColor Green
    } else {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $conflicts = git diff --name-only --diff-filter=U 2>$null
        $ErrorActionPreference = $prevEAP
        if ($conflicts) {
            Write-Host ""
            Write-Host "  === CONFLICTS ===" -ForegroundColor Red
            foreach ($f in $conflicts) {
                Write-Host "    - $f" -ForegroundColor Yellow
            }
            Write-Host "  See patches/NOLOGIN_CHANGES.md for help." -ForegroundColor Cyan
        }
    }
}

# 5. Remove BOM artifacts
Write-Host "  Removing BOM artifacts..." -ForegroundColor Gray
$bomFiles = @(
    '.vscodeignore',
    'src/extension/chat/vscode-node/hooksOutputChannel.ts',
    'src/extension/chatSessions/vscode-node/chatCustomAgentsService.ts',
    'src/extension/chatSessions/vscode-node/chatPromptFileService.ts',
    'src/extension/common/constants.ts',
    'src/extension/contextKeys/vscode-node/contextKeys.contribution.ts',
    'src/extension/conversation/vscode-node/languageModelAccess.ts',
    'src/platform/env/vscode/envServiceImpl.ts',
    'src/platform/github/common/octoKitServiceImpl.ts',
    'src/platform/log/vscode/outputChannelLogTarget.ts'
)
$bomCount = 0
foreach ($f in $bomFiles) {
    $fp = Join-Path $rootDir $f
    if (Test-Path $fp) {
        $bytes = [System.IO.File]::ReadAllBytes($fp)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            [System.IO.File]::WriteAllBytes($fp, [byte[]]$bytes[3..($bytes.Length-1)])
            $bomCount++
        }
    }
}
if ($bomCount -gt 0) {
    Write-Host "  Removed BOM from $bomCount files" -ForegroundColor Gray
}

# 6. Build
if (-not $SkipBuild) {
    Write-Host "[4/4] Building VSIX..." -ForegroundColor Green
    if (Test-Path $buildScript) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        node $buildScript 2>&1
        $ErrorActionPreference = $prevEAP
        Write-Host "  Build finished." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Build script not found: $buildScript" -ForegroundColor Yellow
    }
} else {
    Write-Host "[4/4] Skipping build" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$changed = git diff --name-only 2>$null
$ErrorActionPreference = $prevEAP
$count = ($changed | Where-Object { $_ -ne '' } | Measure-Object).Count
Write-Host " Modified files: $count" -ForegroundColor Gray
Write-Host " Memory doc: patches/NOLOGIN_CHANGES.md" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan