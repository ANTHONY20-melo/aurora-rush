<#
.SYNOPSIS
  Runs the Aurora Rush headless test suite.

.DESCRIPTION
  Boots Godot in --headless mode against tests/TestRunner.tscn and returns the
  engine's exit code: 0 = every suite green, 1 = at least one failure.
  This is the single command used to verify the project; CI and FRY both use it.

.PARAMETER Filter
  Optional substring to run a single suite, e.g. -Filter physics

.EXAMPLE
  .\tools\run_tests.ps1
  .\tools\run_tests.ps1 -Filter ranking
#>
param(
  [string]$Filter = "",
  [string]$Godot = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Godot)) {
  $candidates = @(
    "$env:USERPROFILE\.godot-engine\Godot_v4.3-stable_win64_console.exe",
    "$ProjectRoot\tools\godot\Godot_v4.3-stable_win64_console.exe"
  )
  $Godot = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path $Godot)) {
  Write-Error "Godot console binary not found. Expected one of:`n  $($candidates -join "`n  ")"
  exit 2
}

$stamp = Get-Date -Format "HHmmss"
$stdout = Join-Path $env:TEMP "aurora-tests-$stamp.out.log"
$stderr = Join-Path $env:TEMP "aurora-tests-$stamp.err.log"

$engineArgs = @("--headless", "--path", $ProjectRoot, "res://tests/TestRunner.tscn")
if ($Filter -ne "") { $engineArgs += @("--", "--filter=$Filter") }

$process = Start-Process -FilePath $Godot -ArgumentList $engineArgs `
  -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -PassThru

# Touching .Handle is mandatory: without it .NET does not cache the process
# handle and ExitCode comes back empty, which would make this script report
# success even when the suite failed.
$null = $process.Handle

# Hard bound: a hung suite must fail loudly rather than block a build.
if (-not $process.WaitForExit(180000)) {
  Write-Host "`nTIMEOUT: suite did not finish in 180s. Killing engine." -ForegroundColor Red
  try { $process.Kill() } catch {}
  Get-Content $stdout -ErrorAction SilentlyContinue
  exit 3
}

Get-Content $stdout -ErrorAction SilentlyContinue

$scriptErrors = Get-Content $stderr -ErrorAction SilentlyContinue |
  Select-String -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access'
if ($scriptErrors) {
  Write-Host "`n--- ENGINE SCRIPT ERRORS ---" -ForegroundColor Red
  $scriptErrors | ForEach-Object { $_.Line } | Sort-Object -Unique | ForEach-Object { Write-Host $_ -ForegroundColor Red }
  exit 4
}

$code = $process.ExitCode
if ($null -eq $code) {
  Write-Host "`nCould not read engine exit code -- treating as failure." -ForegroundColor Red
  exit 5
}
if ($code -ne 0) {
  Write-Host "`nSUITE FAILED (exit $code)" -ForegroundColor Red
}
exit $code
