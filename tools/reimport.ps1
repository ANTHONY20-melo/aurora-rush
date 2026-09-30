<#
.SYNOPSIS
  Rebuilds Godot's import + global class-name cache, then reports any script
  errors. Run this after adding or renaming any `class_name` script, otherwise
  the test suite fails with confusing "Could not find type" errors.

.EXAMPLE
  .\tools\reimport.ps1
#>
param([string]$Godot = "")

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Godot)) {
  $candidates = @(
    "$env:USERPROFILE\.godot-engine\Godot_v4.3-stable_win64_console.exe",
    "$ProjectRoot\tools\godot\Godot_v4.3-stable_win64_console.exe"
  )
  $Godot = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Godot) { Write-Error "Godot not found"; exit 2 }

$stdout = Join-Path $env:TEMP "aurora-import.out.log"
$stderr = Join-Path $env:TEMP "aurora-import.err.log"

$process = Start-Process -FilePath $Godot `
  -ArgumentList @("--headless", "--path", $ProjectRoot, "--import") `
  -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -PassThru
$null = $process.Handle
if (-not $process.WaitForExit(180000)) {
  Write-Host "IMPORT TIMEOUT" -ForegroundColor Red; try { $process.Kill() } catch {}; exit 3
}

$errors = Get-Content $stderr -ErrorAction SilentlyContinue |
  Select-String -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load'
if ($errors) {
  Write-Host "--- SCRIPT ERRORS ---" -ForegroundColor Red
  $errors | ForEach-Object { $_.Line } | Sort-Object -Unique | ForEach-Object { Write-Host $_ -ForegroundColor Red }
  exit 1
}

$cache = Join-Path $ProjectRoot ".godot\global_script_class_cache.cfg"
if (-not (Test-Path $cache)) { Write-Host "class cache missing" -ForegroundColor Red; exit 1 }

$classes = (Select-String -Path $cache -Pattern '^"?(class)' ).Count
Write-Host "Import OK. Global class cache present." -ForegroundColor Green
exit 0
