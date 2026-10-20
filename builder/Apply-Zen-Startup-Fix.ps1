# One-time migration helper for an EXISTING ZenBrowserPortable launcher.
# Edits ONLY Data\Profile\user.js; backs up user.js first if it exists.
# This is best-effort. The actual browser may still create a Windows shortcut.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
try {
  $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
  $browser=Join-Path $rootFull 'App\Zen\zen.exe'
  $profile=Join-Path $rootFull 'Data\Profile'
  $userJs=Join-Path $profile 'user.js'
  if (-not (Test-Path -LiteralPath $browser -PathType Leaf)) { throw 'App\Zen\zen.exe not found. Run this from an extracted ZenBrowserPortable installation.' }
  if (@(Get-Process -Name zen -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Close Zen completely before applying startup preferences.' }
  foreach ($directory in @((Join-Path $rootFull 'Data'),$profile)) {
    if (Test-Path -LiteralPath $directory) {
      $item=Get-Item -LiteralPath $directory -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing profile directory symlink/junction.' }
    }
  }
  New-Item -ItemType Directory -Force -Path $profile | Out-Null
  if (Test-Path -LiteralPath $userJs) {
    $item=Get-Item -LiteralPath $userJs -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing linked user.js.' }
    $current=[IO.File]::ReadAllText($userJs)
  } else { $current='' }
  $new=$current
  foreach ($pref in @('browser.shell.customIcon.enabled','browser.privacySegmentation.enabled')) {
    $pattern='(?m)^[ \t]*user_pref\([ \t]*"'+[regex]::Escape($pref)+'"[ \t]*,[ \t]*(?:true|false)[ \t]*\);[ \t]*\r?\n?'
    $new=[regex]::Replace($new,$pattern,'')
    $new=$new.TrimEnd([char[]]@("`r","`n")) + "`r`n" + 'user_pref("' + $pref + '", false);' + "`r`n"
  }
  if ($new -ceq $current) {
    Write-Host 'Startup preferences already configured; nothing changed.' -ForegroundColor Green
    exit 0
  }
  if (Test-Path -LiteralPath $userJs) {
    $dir=Join-Path $rootFull 'Data\UpdaterCleanup\Backups'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $backup=Join-Path $dir ('user.js.before-shortcut-fix-'+ (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.bak')
    Copy-Item -LiteralPath $userJs -Destination $backup -ErrorAction Stop
    Write-Host "Backed up original user.js: $backup"
  }
  [IO.File]::WriteAllText($userJs,$new,(New-Object System.Text.UTF8Encoding($false)))
  Write-Host 'Applied best-effort Zen shortcut-prevention preferences to Data\Profile\user.js.' -ForegroundColor Green
  Write-Host 'Other browser settings, bookmarks, extensions and saved passwords were not changed.'
  Write-Host 'Your post-exit shortcut cleanup remains necessary if Zen ignores these preferences.'
} catch {
  Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red
  exit 1
}
