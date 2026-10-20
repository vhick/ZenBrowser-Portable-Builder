# Zen Browser Portable - automatic, install-specific cleanup (Windows PowerShell 5.1).
# The launcher passes the currently computed Mozilla install hash without prompting.
# No recursive ProgramData deletion, no elevation, never touch other install hashes.
# Unknown files, linked paths and nonempty shared directories are preserved.
[CmdletBinding()]
param(
  [ValidateSet('Clean','Check')][string]$Mode = 'Check',
  [Parameter(Mandatory=$true)][string]$Root,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9A-Fa-f]{1,16}$')][string]$InstallHash
)
$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$dataPath = Join-Path $rootPath 'Data\UpdaterCleanup'
# Identified by the launcher using Mozilla's CityHash64 install-directory scheme.
# There is no manual approval and no roaming machine-specific path in Data.
$mozillaRoot = Join-Path $env:ProgramData 'Mozilla-1de4eec8-1241-4177-a864-e594e8d1fb38'
$autoFolder = Join-Path (Join-Path $mozillaRoot 'updates') ($InstallHash.ToUpperInvariant())
# Legacy machine-specific approvals are deliberately ignored after a move/reformat.
$logPath = Join-Path $dataPath 'cleanup.log'
New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
function Log([string]$msg) {
  $record = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $msg
  Add-Content -LiteralPath $logPath -Encoding UTF8 -Value $record
  Write-Host $record
}
function Canonical([string]$p) { return [IO.Path]::GetFullPath($p.Trim().Trim('"')).TrimEnd('\') }
function Validate-Folder([string]$inputPath) {
  if ([string]::IsNullOrWhiteSpace($inputPath)) { throw 'Update Folder path is empty.' }
  $p = Canonical $inputPath
  if ([IO.Path]::GetFileName($p) -ieq 'update-config.json') {
    $p = [IO.Path]::GetDirectoryName($p)
  }
  $pd = Canonical $env:ProgramData
  $pdPrefix = $pd + '\'
  if (-not $p.StartsWith($pdPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing a folder outside Windows ProgramData.'
  }
  $relative = $p.Substring($pdPrefix.Length)
  $parts = $relative.Split('\')
  if ($parts.Length -ne 3 -or $parts[1] -ine 'updates') {
    throw 'Expected ProgramData\Mozilla-{GUID}\updates\{16 hex digit installation ID}.'
  }
  $match = [regex]::Match($parts[0], '^Mozilla-([0-9a-fA-F-]{36})$', 'IgnoreCase')
  $guid = [guid]::Empty
  if (-not $match.Success -or -not [guid]::TryParse($match.Groups[1].Value, [ref]$guid)) {
    throw 'Not a recognized Mozilla update root.'
  }
  if ($parts[2] -cnotmatch '^[0-9a-fA-F]{1,16}$') { throw 'Unexpected update folder ID.' }
  # A junction or symbolic link anywhere in the path can redirect deletion.
  $cursor = $pd
  foreach ($part in $parts) {
    $cursor = Join-Path $cursor $part
    if (Test-Path -LiteralPath $cursor) {
      $item = Get-Item -LiteralPath $cursor -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing linked/junction path: $cursor"
      }
      if (-not $item.PSIsContainer) { throw "Expected directory at $cursor" }
    }
  }
  return $p
}
function No-Zen-Processes {
  # Conservative: do not touch update state if ANY Zen process exists, including installed Zen.
  return (@(Get-Process -Name zen -ErrorAction SilentlyContinue).Count -eq 0)
}
function Wait-For-ZenExit([int]$maxSeconds = 18) {
  # On Windows, Zen's secondary processes can outlive the process the launcher waited on.
  # The old cleanup checked once, too early, and then never retried.
  # IMPORTANT: Do not terminate or ignore live Zen processes just to force cleanup.
  $elapsed = 0
  $announced = $false
  while ($true) {
    $active = @(Get-Process -Name zen -ErrorAction SilentlyContinue)
    if ($active.Count -eq 0) {
      if ($announced) { Log "Zen finished closing after $elapsed seconds; cleanup can proceed." }
      return $true
    }
    $details = ($active | ForEach-Object {
      $exePath = '[path unavailable]'
      try { if ($_.Path) { $exePath = $_.Path } } catch { }
      ('PID={0}, Path={1}' -f $_.Id, $exePath)
    }) -join ' | '
    if (-not $announced) {
      Log "Zen is still exiting. Waiting up to $maxSeconds seconds: $details"
      $announced = $true
    }
    if ($elapsed -ge $maxSeconds) {
      Log "SKIP: zen.exe still running after $maxSeconds seconds: $details"
      return $false
    }
    Start-Sleep -Seconds 2
    $elapsed += 2
  }
}
function Is-PlainFile([string]$p) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $false }
  return ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
}
function Remove-IfEmpty([string]$p) {
  if (-not (Test-Path -LiteralPath $p -PathType Container)) { return }
  $info = Get-Item -LiteralPath $p -Force
  if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
  if (@(Get-ChildItem -LiteralPath $p -Force).Count -eq 0) {
    Remove-Item -LiteralPath $p -Force
    Log "Removed empty directory: $p"
  }
}
function Clean-Empty-Zen-AppData {
  foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA)) {
    if ([string]::IsNullOrEmpty($base)) { continue }
    $dir = Join-Path $base 'zen'
    # Remove ONLY empty folders. Never remove any profile, cached data, or other files.
    if ($base -eq $env:APPDATA) { Remove-IfEmpty (Join-Path $dir 'Profiles') }
    Remove-IfEmpty $dir
  }
}
# Clean only the exact Zen-specific remnants requested by the user. Both .lnk
# files require a verified target inside THIS portable package. Other Zen
# installations and arbitrary Mozilla/Firefox files are always left alone.
function Test-PortableShortcut([string]$linkPath) {
  try {
    $wsh = New-Object -ComObject WScript.Shell
    $link = $wsh.CreateShortcut($linkPath)
    $target = [string]$link.TargetPath
    if ([string]::IsNullOrWhiteSpace($target)) {
      Log "SKIP: shortcut target cannot be verified: $linkPath"
      return $false
    }
    $actual = Canonical ([Environment]::ExpandEnvironmentVariables($target))
    $portableExe = Canonical (Join-Path $rootPath 'ZenBrowserPortable.exe')
    $zenExe = Canonical (Join-Path $rootPath 'App\Zen\zen.exe')
    # Mozilla-based browsers have a second executable that opens private windows.
    # Exact-match it only inside THIS portable installation, not arbitrary names.
    $privateExe = Canonical (Join-Path $rootPath 'App\Zen\private_browsing.exe')
    if ($actual -ieq $portableExe -or $actual -ieq $zenExe -or $actual -ieq $privateExe) { return $true }
    Log "SKIP: shortcut belongs to a different target ($target): $linkPath"
    return $false
  } catch {
    Log "SKIP: cannot inspect shortcut $linkPath : $($_.Exception.Message)"
    return $false
  }
}
function Save-And-Remove-Exact([string]$path, [string]$reason) {
  if (-not (Is-PlainFile $path)) { Log "SKIP: not a regular file: $path"; return }
  if (-not (No-Zen-Processes)) { Log "SKIP: Zen started again; leaving: $path"; return }
  $backupFolder = Join-Path $dataPath ('Backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-ZenRemnants')
  New-Item -ItemType Directory -Force -Path $backupFolder | Out-Null
  $backupFile = Join-Path $backupFolder ([IO.Path]::GetFileName($path))
  Copy-Item -LiteralPath $path -Destination $backupFile -ErrorAction Stop
  if (-not (Test-Path -LiteralPath $backupFile -PathType Leaf)) { throw "Backup failed for $path" }
  if (-not (No-Zen-Processes)) { Log "SKIP: Zen restarted after backup; leaving: $path"; return }
  Remove-Item -LiteralPath $path -Force -ErrorAction Stop
  Log "Removed $reason : $path (backup: $backupFile)"
}
function Test-NoLinkedAncestors([string]$path, [string]$trustedRoot) {
  $candidate = Canonical $path
  $base = Canonical $trustedRoot
  if (-not $candidate.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
  $cursor = $base
  foreach ($piece in $candidate.Substring($base.Length + 1).Split('\')) {
    $cursor = Join-Path $cursor $piece
    if (Test-Path -LiteralPath $cursor) {
      if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    }
  }
  return $true
}
function Clean-Portable-StartMenu-Shortcuts {
  $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  $names = @('Zen.lnk', '{-brand-shortcut-name} Private Browsing.lnk', '{ -brand-shortcut-name } Private Browsing.lnk')
  foreach ($name in $names) {
    $path = Join-Path $programs $name
    if (-not (Test-Path -LiteralPath $path)) { Log "Not present: $path"; continue }
    if (-not (Test-NoLinkedAncestors $path $env:APPDATA)) { Log "SKIP: shortcut path contains a link or junction: $path"; continue }
    if (-not (Is-PlainFile $path)) { Log "SKIP: shortcut is not a plain file: $path"; continue }
    if (-not (Test-PortableShortcut $path)) { continue }
    try { Save-And-Remove-Exact $path 'verified portable Zen Start Menu shortcut' }
    catch { Log "SKIP/ERROR: shortcut cleanup failed for $path : $($_.Exception.Message)" }
  }
}
function Clean-Approved-Zen-Shortcut-State([string]$mozillaRoot) {
  # Zen's Windows per-user shortcut state file. Match the current SID exactly;
  # do not wildcard/delete other users' INI files or other products' files.
  try {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $ini = Join-Path $mozillaRoot ('Zen_' + $sid + '_shortcuts.ini')
    if (-not (Test-Path -LiteralPath $ini)) { Log "Not present: $ini"; return }
    if (-not (Test-NoLinkedAncestors $ini $env:ProgramData)) { Log "SKIP: INI path has a linked directory: $ini"; return }
    if (-not (Is-PlainFile $ini)) { Log "SKIP: INI is not a regular file: $ini"; return }
    $info = Get-Item -LiteralPath $ini -Force
    if ($info.Length -gt 524288) { Log "SKIP: unusually large Zen shortcut INI: $ini"; return }
    $body = Get-Content -LiteralPath $ini -Raw -ErrorAction Stop
    # If the file explicitly refers to a different installed Zen executable,
    # retain it. The format is not sufficiently documented to remove its data
    # on name alone when another installation is clearly referenced.
    $portableExe = Canonical (Join-Path $rootPath 'App\Zen\zen.exe')
    if ($null -eq $body) { $body = '' }
    $foreignZen = [regex]::Matches($body, '(?i)[A-Z]:\\[^\r\n"<>|]*?\\zen\.exe')
    foreach ($m in $foreignZen) {
      if (-not ($m.Value -ieq $portableExe)) {
        Log "SKIP: shortcut INI mentions another Zen installation; retained: $ini"
        return
      }
    }
    Save-And-Remove-Exact $ini 'approved current-user Zen shortcut state INI'
  } catch {
    Log "SKIP/ERROR: Zen shortcuts.ini cleanup: $($_.Exception.Message)"
  }
}
function Report-And-Prune-Empty-MozillaUpdates([string]$updatesRoot) {
  if (-not (Test-Path -LiteralPath $updatesRoot)) { Log "Not present: $updatesRoot"; return }
  if (-not (Test-Path -LiteralPath $updatesRoot -PathType Container)) { Log "SKIP: updates path is not a directory: $updatesRoot"; return }
  if (-not (Test-NoLinkedAncestors $updatesRoot $env:ProgramData)) { Log "SKIP: linked Mozilla updates directory: $updatesRoot"; return }
  $children = @(Get-ChildItem -LiteralPath $updatesRoot -Force -ErrorAction Stop)
  if ($children.Count -ne 0) {
    $names = ($children | Select-Object -First 8 | ForEach-Object { $_.Name }) -join ', '
    Log "RETAINED: shared Mozilla updates directory is not empty ($($children.Count) items: $names): $updatesRoot"
    return
  }
  if (-not (No-Zen-Processes)) { Log "SKIP: Zen restarted; leaving updates directory: $updatesRoot"; return }
  Remove-IfEmpty $updatesRoot
}

function Report-And-Prune-Empty-MozillaRoot([string]$mozillaRoot) {
  # The Mozilla GUID directory can contain content from other installations.
  # We only prune the exact approved parent when truly empty; NO recursive delete.
  if (-not (Test-Path -LiteralPath $mozillaRoot)) {
    Log "Mozilla parent already absent: $mozillaRoot"
    return
  }
  if (-not (Test-Path -LiteralPath $mozillaRoot -PathType Container)) {
    Log "RETAINED: Mozilla parent path is not a directory: $mozillaRoot"
    return
  }
  if (-not (Test-NoLinkedAncestors $mozillaRoot $env:ProgramData)) {
    Log "RETAINED: linked/junction Mozilla parent: $mozillaRoot"
    return
  }
  if (-not ([IO.Path]::GetFileName((Canonical $mozillaRoot)) -match '^Mozilla-[0-9a-fA-F-]{36}$')) {
    Log "RETAINED: Mozilla parent does not match approved GUID layout: $mozillaRoot"
    return
  }
  try {
    $remaining = @(Get-ChildItem -LiteralPath $mozillaRoot -Force -ErrorAction Stop)
    if ($remaining.Count -gt 0) {
      $names = ($remaining | Select-Object -First 20 | ForEach-Object {
        if ($_.PSIsContainer) { '[folder] ' + $_.Name } else { '[file] ' + $_.Name }
      }) -join '; '
      Log "RETAINED: Mozilla parent contains $($remaining.Count) item(s): $names : $mozillaRoot"
      return
    }
    if (-not (No-Zen-Processes)) {
      Log "RETAINED: Zen restarted before Mozilla parent cleanup: $mozillaRoot"
      return
    }
    # PowerShell will refuse to remove a nonempty folder without -Recurse.
    # Thus a file arriving between check and removal stays protected.
    Remove-Item -LiteralPath $mozillaRoot -Force -ErrorAction Stop
    Log "Removed EMPTY approved Mozilla parent directory: $mozillaRoot"
  } catch {
    Log "RETAINED/ERROR: could not inspect/remove Mozilla parent: $mozillaRoot : $($_.Exception.Message)"
  }
}

function Clean-Approved([string]$approved) {
  $folder = Validate-Folder $approved
  $policyPath = Join-Path $rootPath 'App\Zen\distribution\policies.json'
  if (-not (Test-Path -LiteralPath (Join-Path $rootPath 'App\Zen\zen.exe') -PathType Leaf)) {
    Log 'SKIP: inner Zen program missing.'; return
  }
  try { $policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json }
  catch { Log 'SKIP: cannot verify portable update-disable policy.'; return }
  if ($policy.policies.DisableAppUpdate -ne $true) {
    Log 'SKIP: DisableAppUpdate is not true in bundled policy.'; return
  }
  if (-not (Wait-For-ZenExit 18)) { return }
  # The approved update folder may be absent while the installation-specific
  # UpdateLock still exists at the Mozilla root. This is normal on Firefox-family
  # applications and must be handled separately (without broad root deletion).
  $installationId = Split-Path -Path $folder -Leaf
  $updatesRoot = Split-Path -Path $folder -Parent
  $mozillaRoot = Split-Path -Path $updatesRoot -Parent
  $updateLock = Join-Path $mozillaRoot ('UpdateLock-' + $installationId)
  # Narrowly scoped Windows remnants; every deletion is logged and backed up.
  Clean-Approved-Zen-Shortcut-State $mozillaRoot
  if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
    Log "Approved update folder does not exist: $folder"
    if (Test-Path -LiteralPath $updateLock) {
      if (-not (Is-PlainFile $updateLock)) {
        Log 'SKIP: approved lock is not a plain file.'
      } elseif ((Get-Item -LiteralPath $updateLock -Force).Length -ne 0) {
        Log 'SKIP: approved lock is not zero-byte (unexpected content).'
      } else {
        # Never delete a file until its same-hash ownership has been approved,
        # the data backup succeeds, and no Zen process is running.
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
        $backupDir = Join-Path $dataPath ('Backups\' + $stamp)
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Copy-Item -LiteralPath $updateLock -Destination (Join-Path $backupDir ([IO.Path]::GetFileName($updateLock))) -ErrorAction Stop
        if (-not (No-Zen-Processes)) {
          Log 'SKIP: Zen restarted before lock cleanup.'
        } else {
          Remove-Item -LiteralPath $updateLock -Force -ErrorAction Stop
          Log "Removed approved zero-byte lock: $updateLock"
        }
      }
    } else {
      Log 'No approved update lock exists.'
    }
    Report-And-Prune-Empty-MozillaUpdates $updatesRoot
    Report-And-Prune-Empty-MozillaRoot $mozillaRoot
    Clean-Empty-Zen-AppData
    Log 'Cleanup complete (approved update folder already absent).'
    return
  }
  $allowFiles = @('update-config.json','parent.lock')
  $allowDirs = @('updates')
  # If unknown files/subfolders appear, DO NOT DELETE anything in ProgramData.
  foreach ($item in @(Get-ChildItem -LiteralPath $folder -Force)) {
    if ($item.PSIsContainer) {
      if ($item.Name -notin $allowDirs) { Log "SKIP: unknown folder $($item.Name)"; return }
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Log 'SKIP: linked updater directory.'; return }
      foreach ($sub in @(Get-ChildItem -LiteralPath $item.FullName -Force)) {
        if (-not $sub.PSIsContainer -or $sub.Name -notin @('0','downloading') -or
            ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            @(Get-ChildItem -LiteralPath $sub.FullName -Force).Count -ne 0) {
          Log 'SKIP: update files or unfamiliar directories exist.'; return
        }
      }
    } elseif ($item.Name -notin $allowFiles -or
              ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 131072) {
      Log "SKIP: unrecognized/large update file $($item.Name)"; return
    }
  }
  if (Test-Path -LiteralPath $updateLock) {
    if (-not (Is-PlainFile $updateLock)) { Log 'SKIP: update lock is not a normal file.'; return }
    if ((Get-Item -LiteralPath $updateLock -Force).Length -ne 0) {
      Log 'SKIP: unexpected non-empty update lock.'; return
    }
  }
  # Ensure backups complete before any deletions. The backup remains in portable Data.
  $files = @()
  foreach ($name in $allowFiles) {
    $file = Join-Path $folder $name
    if (Test-Path -LiteralPath $file) { $files += $file }
  }
  if (Test-Path -LiteralPath $updateLock) { $files += $updateLock }
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
  $backup = Join-Path $dataPath ('Backups\' + $stamp)
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  foreach ($file in $files) {
    Copy-Item -LiteralPath $file -Destination (Join-Path $backup ([IO.Path]::GetFileName($file))) -ErrorAction Stop
  }
  if (-not (No-Zen-Processes)) { Log 'SKIP: Zen launched again before cleanup.'; return }
  foreach ($file in $files) { Remove-Item -LiteralPath $file -Force -ErrorAction Stop; Log "Removed approved updater file: $file" }
  foreach ($name in @('0','downloading')) { Remove-IfEmpty (Join-Path $folder ('updates\' + $name)) }
  Remove-IfEmpty (Join-Path $folder 'updates')
  Remove-IfEmpty $folder
  # Never remove other hashes; prune the approved Mozilla root ONLY if empty.
  Report-And-Prune-Empty-MozillaUpdates $updatesRoot
  Report-And-Prune-Empty-MozillaRoot $mozillaRoot
  Clean-Empty-Zen-AppData
  Log 'Cleanup complete. Verified Zen shortcut and updater remnants were checked; other installations were preserved.'
}
try {
  $folder = Validate-Folder $autoFolder
  if ($Mode -eq 'Check') {
    Log "Automatic update target for THIS portable directory: $folder"
    exit 0
  }
  if (-not (Wait-For-ZenExit 18)) { exit 0 }
  Clean-Portable-StartMenu-Shortcuts
  # This ID must correspond to the directory from the current portable launcher.
  # If the hash is not the one used by Zen, preserve all unrelated Mozilla data.
  Log "Automatic current-install updater check: $folder"
  Clean-Approved $folder
} catch {
  Log "SKIP/ERROR: $($_.Exception.Message)"
  exit 2
}
