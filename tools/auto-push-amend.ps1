param(
  [string]$Path = (Get-Location).Path,
  [string]$Branch = "mirror",
  [int]$IntervalSec = 90,      # push cadence in seconds
  [int]$DebounceMs = 800       # debounce file change bursts
)
$ErrorActionPreference = "Stop"
Set-Location $Path

if (-not (Test-Path ".git")) { git init | Out-Null }
if (-not (git rev-parse --verify $Branch 2>$null)) { git checkout -b $Branch | Out-Null } else { git checkout $Branch | Out-Null }

$remotes = (git remote) -split "\r?\n"
if ($remotes -notcontains "origin") {
  Write-Host "FAIL: add remote: git remote add origin <URL>" -ForegroundColor Red
  exit 1
}

function Invoke-Push {
  $status = git status --porcelain
  if (-not $status) { return }
  git add -A
  $hasHead = (git rev-parse --verify HEAD 2>$null)
  if ($hasHead) {
    git commit --amend --no-edit --allow-empty -q
  } else {
    git commit -m ("mirror: init " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -q
  }
  git push -f origin $Branch -q
  Write-Host ("Pushed (amend) {0}" -f (Get-Date -Format "HH:mm:ss")) -ForegroundColor Green
}

$fsw = New-Object IO.FileSystemWatcher $Path -Property @{ IncludeSubdirectories=$true; Filter='*.*'; EnableRaisingEvents=$true }
$pending = $false
$deb = New-Object Timers.Timer($DebounceMs); $deb.AutoReset = $false
$interval = New-Object Timers.Timer($IntervalSec * 1000); $interval.AutoReset = $true

Register-ObjectEvent -InputObject $deb -EventName Elapsed -Action { $script:pending = $true } | Out-Null
Register-ObjectEvent -InputObject $interval -EventName Elapsed -Action { if ($script:pending) { $script:pending = $false; Invoke-Push } } | Out-Null

$handler = { $deb.Stop(); $deb.Start() }
'Changed','Created','Renamed','Deleted' | ForEach-Object { Register-ObjectEvent $fsw $_ -Action $handler | Out-Null }

Write-Host "Watching $Path → '$Branch' (amend/force-push every $IntervalSec s if changed). Ctrl+C to stop."
$interval.Start()
while ($true) { Start-Sleep -Seconds 1 }
