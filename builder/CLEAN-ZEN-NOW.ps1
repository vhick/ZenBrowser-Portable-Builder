# Manual Zen Portable cleanup helper. Shortcut cleanup is always scoped and enabled.
# Never skips the active-process safety check or deletes browser profile data.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cleaner = Join-Path $PSScriptRoot 'ZenUpdateCleanup.ps1'
$log = Join-Path $root 'Data\UpdaterCleanup\cleanup.log'

Write-Host ''
Write-Host 'ZEN PORTABLE - CHECK AND CLEAN' -ForegroundColor Cyan
Write-Host 'Portable folder:' $root
Write-Host 'This helper always checks shortcuts linked to THIS portable Zen.'
Write-Host ''

if (-not (Test-Path -LiteralPath (Join-Path $root 'ZenBrowserPortable.exe') -PathType Leaf)) {
    Write-Host 'ERROR: Copy these two helper files into ZenBrowserPortable\Other first.' -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $cleaner -PathType Leaf)) {
    Write-Host 'ERROR: Missing Other\ZenUpdateCleanup.ps1. Keep your existing cleanup script alongside this helper.' -ForegroundColor Red
    exit 2
}

Write-Host 'Checking for running Zen processes ...'
Start-Sleep -Seconds 3
$running = @(Get-Process -Name zen -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-Host ''
    Write-Host 'CLEANUP BLOCKED: Windows currently reports zen.exe running.' -ForegroundColor Yellow
    foreach ($p in $running) {
        $path = '<path unavailable>'
        try { if ($p.Path) { $path = $p.Path } } catch {}
        Write-Host ('  zen.exe  PID={0}  Path={1}' -f $p.Id, $path)
    }
    Write-Host ''
    Write-Host 'What to do:'
    Write-Host '  1. Fully exit every Zen Browser window.'
    Write-Host '  2. Open Task Manager > Details and look for zen.exe.'
    Write-Host '  3. Wait for all zen.exe processes to close (do not end tasks with unsaved work).'
    Write-Host '  4. Double-click CLEAN-ZEN-NOW.cmd again.'
    Write-Host 'The cleanup intentionally refuses to touch shortcuts or updater files while Zen is running.'
    exit 4
}

Write-Host 'No zen.exe processes found. Checking scoped Zen shortcuts, plus approved updater remnants (if enabled) ...' -ForegroundColor Green
Write-Host ''
try {
    & $cleaner -Mode Clean -Root $root
} catch {
    Write-Host ('Cleanup script error: ' + $_.Exception.Message) -ForegroundColor Red
    exit 5
}
Write-Host ''
if (Test-Path -LiteralPath $log) {
    Write-Host 'Latest cleanup log lines:' -ForegroundColor Cyan
    Get-Content -LiteralPath $log -Tail 12 | ForEach-Object { Write-Host $_ }
} else {
    Write-Host 'No cleanup log was created. Please share this output for diagnosis.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'The script always checks portable-target Start Menu shortcuts.'
Write-Host 'Zen shortcut-state INI and ProgramData updater cleanup remain opt-in.'
Write-Host 'A shortcut is removed only if its target is THIS portable Zen installation.'
Write-Host 'The approved Mozilla GUID parent is removed only if empty; nonempty contents are logged.'
Write-Host 'Your Data\Profile, other installs and nonempty AppData folders are untouched.'
