# Per-session, read-only ProgramData inventory with conservative candidate selection.
# Windows PowerShell 5.1. No elevation; this script NEVER deletes host files.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Before','After')][string]$Mode,
  [Parameter(Mandatory=$true)][string]$Root
)
$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$dataDir = Join-Path $rootPath 'Data\UpdaterCleanup\ProgramDataTracker'
$baselineFile = Join-Path $dataDir 'baseline.json'
$candidateFile = Join-Path $dataDir 'session-candidate.txt'
$logFile = Join-Path $dataDir 'tracker.log'
$mozilla = Join-Path $env:ProgramData 'Mozilla-1de4eec8-1241-4177-a864-e594e8d1fb38'
$updateRoot = Join-Path $mozilla 'updates'
$otherProcesses = @('firefox','thunderbird','updater','maintenanceservice')
New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
function Log([string]$message) {
  Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message)
}
function Is-PlainFile([string]$path) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
  $it = Get-Item -LiteralPath $path -Force -ErrorAction Stop
  return (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
}
function Is-PlainDir([string]$path) {
  if (-not (Test-Path -LiteralPath $path -PathType Container)) { return $false }
  $it = Get-Item -LiteralPath $path -Force -ErrorAction Stop
  return (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
}
function Snapshot {
  $ids = @()
  $locks = @()
  $unsafe = $false
  if (Test-Path -LiteralPath $mozilla) {
    if (-not (Is-PlainDir $mozilla)) { $unsafe = $true }
    else {
      if (Test-Path -LiteralPath $updateRoot) {
        if (-not (Is-PlainDir $updateRoot)) { $unsafe = $true }
        else {
          foreach($d in @(Get-ChildItem -LiteralPath $updateRoot -Directory -Force -ErrorAction Stop)) {
            if ($d.Name -cmatch '^[0-9A-Fa-f]{16}$') {
              if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $unsafe = $true }
              else { $ids += $d.Name.ToUpperInvariant() }
            }
          }
        }
      }
      foreach($f in @(Get-ChildItem -LiteralPath $mozilla -File -Force -ErrorAction Stop)) {
        if ($f.Name -match '^UpdateLock-([0-9A-Fa-f]{16})$') {
          if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $unsafe = $true }
          else { $locks += $Matches[1].ToUpperInvariant() }
        }
      }
    }
  }
  $others = @()
  foreach ($name in $otherProcesses) {
    if (@(Get-Process -Name $name -ErrorAction SilentlyContinue).Count -ne 0) { $others += $name }
  }
  return [pscustomobject]@{
    UpdateIds = @($ids | Sort-Object -Unique)
    LockIds = @($locks | Sort-Object -Unique)
    OtherMozillaProcesses = @($others)
    Unsafe = [bool]$unsafe
  }
}
function Is-RecognizedNewFolder([string]$id) {
  $folder = Join-Path $updateRoot $id
  if (-not (Is-PlainDir $folder)) { return $false }
  $config = Join-Path $folder 'update-config.json'
  $lock = Join-Path $mozilla ('UpdateLock-' + $id)
  if (-not (Is-PlainFile $config) -or -not (Is-PlainFile $lock)) { return $false }
  if ((Get-Item -LiteralPath $config -Force).Length -gt 131072) { return $false }
  if ((Get-Item -LiteralPath $lock -Force).Length -ne 0) { return $false }
  $allowed = @('update-config.json','parent.lock')
  foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)) {
    if ($item.PSIsContainer -or $item.Name -notin $allowed -or
       ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $item.Length -gt 131072) { return $false }
  }
  return $true
}
try {
  if ($Mode -eq 'Before') {
    # Never reuse a previous session's candidate.
    if (Test-Path -LiteralPath $candidateFile) { Remove-Item -LiteralPath $candidateFile -Force }
    if (Test-Path -LiteralPath $baselineFile) { Remove-Item -LiteralPath $baselineFile -Force }
    $baseline = Snapshot
    $state = [pscustomobject]@{
      StartedUtc = (Get-Date).ToUniversalTime().ToString('o')
      InstallRoot = $rootPath
      ProgramData = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\')
      Snapshot = $baseline
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $baselineFile -Encoding UTF8
    Log ('BEFORE: IDs=' + (@($baseline.UpdateIds) -join ',') + '; locks=' + (@($baseline.LockIds) -join ',') + '; other processes=' + (@($baseline.OtherMozillaProcesses) -join ',') + '; unsafe=' + $baseline.Unsafe)
    exit 0
  }
  if (-not (Test-Path -LiteralPath $baselineFile -PathType Leaf)) { throw 'Missing matching pre-launch inventory.' }
  $baseline = Get-Content -LiteralPath $baselineFile -Raw | ConvertFrom-Json
  # Consume the baseline, and fail closed on missing or mismatched session state.
  Remove-Item -LiteralPath $baselineFile -Force
  if ($baseline.InstallRoot -ine $rootPath -or $baseline.ProgramData -ine ([IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\'))) { throw 'Computer/path changed since baseline.' }
  $now = Snapshot
  $previous = $baseline.Snapshot
  Log ('AFTER: IDs=' + (@($now.UpdateIds) -join ',') + '; locks=' + (@($now.LockIds) -join ',') + '; other processes=' + (@($now.OtherMozillaProcesses) -join ',') + '; unsafe=' + $now.Unsafe)
  if ($previous.Unsafe -or $now.Unsafe) { Log 'NO CANDIDATE: linked or unsafe path.'; exit 0 }
  if (@($previous.OtherMozillaProcesses | Where-Object { $_ }).Count -gt 0 -or @($now.OtherMozillaProcesses | Where-Object { $_ }).Count -gt 0) {
    Log 'NO CANDIDATE: other Mozilla updater/browser process found; ownership ambiguous.'; exit 0
  }
  if (@(Get-Process -Name zen -ErrorAction SilentlyContinue).Count -ne 0) {
    Log 'NO CANDIDATE: Zen still running.'; exit 0
  }
  # A diff does not prove causality. Accept only a SINGLE paired folder + lock
  # newly observed in this session, with the expected constrained file layout.
  $newDirs = @(@($now.UpdateIds) | Where-Object { $_ -notin @($previous.UpdateIds) })
  $newLocks = @(@($now.LockIds) | Where-Object { $_ -notin @($previous.LockIds) })
  $paired = @($newDirs | Where-Object { $_ -in $newLocks })
  if ($newDirs.Count -ne 1 -or $newLocks.Count -ne 1 -or $paired.Count -ne 1) {
    Log ('NO CANDIDATE: additions are not a unique new folder + lock pair; new folders=' + ($newDirs -join ',') + '; locks=' + ($newLocks -join ','))
    exit 0
  }
  $id = [string]$paired[0]
  if (-not (Is-RecognizedNewFolder $id)) { Log ('NO CANDIDATE: files in ' + $id + ' do not pass strict allowlist.'); exit 0 }
  Set-Content -LiteralPath $candidateFile -Value $id -Encoding Ascii
  Log ('CANDIDATE: ' + $id + ' observed as one new folder + zero-byte lock; cleanup helper must still validate and back up.')
  exit 0
} catch {
  Log ('TRACKER ERROR: ' + $_.Exception.Message)
  exit 2
}
