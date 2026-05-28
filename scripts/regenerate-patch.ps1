<#
.SYNOPSIS
    从当前工作区的修改重新生成 nologin.patch
.DESCRIPTION
    当你手动修改了 NoLogin 相关代码后，运行此脚本更新 patch 文件。
#>

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$patchFile = Join-Path $rootDir "patches\nologin.patch"

Set-Location $rootDir

Write-Host "Regenerating nologin.patch..." -ForegroundColor Cyan

# Generate patch from all unstaged changes
git diff > $patchFile

$size = (Get-Item $patchFile).Length
$lines = (Get-Content $patchFile | Measure-Object).Count

Write-Host "  Patch file: $patchFile" -ForegroundColor Gray
Write-Host "  Size: $size bytes, $lines lines" -ForegroundColor Gray

# List changed files
$files = git diff --name-only 2>&1
Write-Host ""
Write-Host "  Files in patch:" -ForegroundColor Gray
foreach ($f in $files) {
    Write-Host "    - $f" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Done! Patch file updated." -ForegroundColor Green