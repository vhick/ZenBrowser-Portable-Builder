# Zen Browser Portable: user-only, pre/post registry snapshot and restore.
# Only HKCU\Software\Mozilla\Zen is in scope. Never touches HKLM or sibling Mozilla apps.
# Windows PowerShell 5.1; automatically called by ZenBrowserPortable.exe.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Before','After')][string]$Mode,
  [Parameter(Mandatory=$true)][string]$Root
)
$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')
$base=Join-Path $rootPath 'Data\HostEnvironment\Registry'
$session=Join-Path $base 'CurrentSession'
$history=Join-Path $base 'History'
$stateFile=Join-Path $session 'state.json'
$beforeReg=Join-Path $session 'before.reg'
$afterReg=Join-Path $session 'after.reg'
$regExe=Join-Path $env:SystemRoot 'System32\reg.exe'
$regKey='HKCU\Software\Mozilla\Zen'
$psKey='Registry::HKEY_CURRENT_USER\Software\Mozilla\Zen'
$logFile=Join-Path $base 'registry.log'
New-Item -ItemType Directory -Path $base -Force | Out-Null
function Log([string]$message) {
  ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message) |
    Out-File -LiteralPath $logFile -Encoding utf8 -Append
}
function Invoke-Reg([string[]]$regArgs) {
  & $regExe @regArgs | Out-Null
  if ($LASTEXITCODE -ne 0) { throw ('reg.exe {0} failed (exit {1})' -f ($regArgs[0]),$LASTEXITCODE) }
}
function Check-No-Zen {
  if (@(Get-Process -Name zen -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Zen is running: cannot safely snapshot/restore shared Zen registry entries.'
  }
}
try {
  if ($Mode -eq 'Before') {
    Check-No-Zen
    if (Test-Path -LiteralPath $session) {
      # A previously interrupted session must not be mistaken for this PC's
      # baseline. Preserve its evidence and take a fresh snapshot, never import it.
      New-Item -ItemType Directory -Path $history -Force | Out-Null
      $old=Join-Path $history ('Unfinished-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
      Move-Item -LiteralPath $session -Destination $old -ErrorAction Stop
      Log 'WARNING: Previous interrupted session archived. Its registry state was not automatically reverted.'
    }
    New-Item -ItemType Directory -Path $session -Force | Out-Null
    $exists=Test-Path -LiteralPath $psKey
    if ($exists) { Invoke-Reg @('export',$regKey,$beforeReg,'/y') }
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $state=[ordered]@{
      Computer=$env:COMPUTERNAME
      Sid=$sid
      Existed=$exists
      Started=(Get-Date).ToString('o')
    }
    $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
    Log ('Pre-launch Zen registry snapshot saved (pre-existing keys: ' + $exists + ').')
    exit 0
  }
  if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) {
    Log 'WARNING: No current-session registry snapshot, so registry was not changed.'
    exit 3
  }
  Check-No-Zen
  $state=Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  if ($state.Computer -cne $env:COMPUTERNAME -or $state.Sid -cne $sid) {
    throw 'Snapshot was created for another Windows machine/user. No registry change made.'
  }
  $currentlyExists=Test-Path -LiteralPath $psKey
  if ($currentlyExists) { Invoke-Reg @('export',$regKey,$afterReg,'/y') }
  if ($state.Existed) {
    if (-not (Test-Path -LiteralPath $beforeReg -PathType Leaf)) {
      throw 'Pre-existing Zen registry backup missing; refusing to delete registry key.'
    }
    if ($currentlyExists) { Invoke-Reg @('delete',$regKey,'/f') }
    try { Invoke-Reg @('import',$beforeReg) }
    catch {
      # Re-import post-session state if original cannot be restored.
      if (Test-Path -LiteralPath $afterReg -PathType Leaf) {
        try { Invoke-Reg @('import',$afterReg) } catch { Log 'CRITICAL: Both baseline and fallback registry restore failed.' }
      }
      throw
    }
    Log 'Restored complete pre-launch HKCU Mozilla Zen registry state.'
  } else {
    # The key did not exist before starting the portable browser.
    if ($currentlyExists) { Invoke-Reg @('delete',$regKey,'/f') }
    Log 'Removed newly created HKCU Mozilla Zen registry key (absent before launch).'
  }
  # Keep before/after exports for recovery, but remove active marker.
  New-Item -ItemType Directory -Path $history -Force | Out-Null
  $archived=Join-Path $history ('Completed-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  Move-Item -LiteralPath $session -Destination $archived -ErrorAction Stop
  Log ('Registry check complete; snapshot archived: ' + $archived)
  exit 0
} catch {
  Log ('ERROR: ' + $_.Exception.Message)
  Write-Error $_.Exception.Message
  exit 2
}
