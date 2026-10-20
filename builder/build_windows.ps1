param(
  [Parameter(Mandatory=$true)][string]$Version,
  [ValidateSet('x64','arm64')][string]$Architecture = 'x64'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$repo = (Resolve-Path .).Path
$work = Join-Path $repo 'build-temp'
$out = Join-Path $repo 'artifacts'
$package = Join-Path $work 'ZenBrowserPortable'
$targetApp = Join-Path $package 'App\Zen'
$appInfo = Join-Path $package 'App\AppInfo'
if ($Version -notmatch '^[0-9]+\.[0-9]+(?:\.[0-9]+)?b$') { throw "Enter an official stable tag such as 1.23.3b" }
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Path $targetApp, $appInfo, (Join-Path $package 'Data\Profile'), (Join-Path $package 'Data\Temp'), (Join-Path $package 'Data\UpdaterCleanup'), (Join-Path $package 'Other'), $out -Force | Out-Null

# Retrieve the exact official tagged release from GitHub, including its published
# asset SHA-256. Do not guess checksums or take installer files from mirrors.
$releaseApi = 'https://api.github.com/repos/zen-browser/desktop/releases/tags/' + [uri]::EscapeDataString($Version)
$headers = @{'User-Agent'='ZenBrowserPortable-Builder'; 'Accept'='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28'}
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
$release = Invoke-RestMethod -Uri $releaseApi -Headers $headers
if ($release.prerelease -or $release.draft -or $release.tag_name -ne $Version) { throw 'Release is not the selected published stable tag' }
$name = if ($Architecture -eq 'arm64') { 'zen.installer-arm64.exe' } else { 'zen.installer.exe' }
$asset = @($release.assets | Where-Object { $_.name -ceq $name })
if ($asset.Count -ne 1) { throw "Expected one official Windows installer named $name, found $($asset.Count)" }
$asset = $asset[0]
if ($asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw 'Release asset has no GitHub SHA-256 digest: refusing unverified download' }
$expectedHash = $Matches[1].ToLowerInvariant()
if ($asset.size -lt 50000000) { throw 'Official Windows installer unexpectedly small' }
$download = Join-Path $work $name
Invoke-WebRequest -Uri $asset.browser_download_url -Headers @{'User-Agent'='ZenBrowserPortable-Builder'} -OutFile $download
$actualHash = (Get-FileHash -Path $download -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) { throw "SHA-256 mismatch: expected $expectedHash got $actualHash" }
Write-Host "Verified official Zen $Version $Architecture ($expectedHash)"

# Official Windows installer is a 7-Zip self-extracting package. Scoop also
# extracts the 'core' folder from the official installer archive.
$sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
if (-not (Test-Path $sevenZip)) { throw '7-Zip missing from Windows runner (expected Program Files\7-Zip\7z.exe)' }
$extract = Join-Path $work 'extracted'
New-Item -ItemType Directory -Path $extract -Force | Out-Null
& $sevenZip x $download "-o$extract" -y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7-Zip extraction failed with $LASTEXITCODE" }
$core = Join-Path $extract 'core'
foreach ($required in @('zen.exe','omni.ja','xul.dll')) {
    if (-not (Test-Path (Join-Path $core $required))) { throw "Expected installer core\$required missing; inspect current upstream installer format" }
}
Copy-Item -Path (Join-Path $core '*') -Destination $targetApp -Recurse -Force

# Local browser update policy; this package is managed only by manual rebuilds.
# This relies on Zen honoring Firefox-compatible distribution policies.
$distribution = Join-Path $targetApp 'distribution'
New-Item -ItemType Directory -Force -Path $distribution | Out-Null
'{"policies":{"DisableAppUpdate":true,"DontCheckDefaultBrowser":true}}' | Set-Content -Path (Join-Path $distribution 'policies.json') -Encoding ascii

# Extract original multi-resolution Zen icon, and create PortableApps Menu icons.
python builder/create_icons.py (Join-Path $targetApp 'zen.exe') $appInfo
if ($LASTEXITCODE -ne 0) { throw 'Official Zen icon extraction failed' }

$numbers = [regex]::Match($Version, '^([0-9]+)\.([0-9]+)(?:\.([0-9]+))?b$')
$patch = if ($numbers.Groups[3].Success) { $numbers.Groups[3].Value } else { '0' }
$numericVersion = "$($numbers.Groups[1].Value).$($numbers.Groups[2].Value).$patch.0"
$appinfoText = @"
[Format]
Type=PortableApps.comFormat
Version=3.9

[Details]
Name=Zen Browser Portable
AppID=ZenBrowserPortableCommunity
Publisher=Zen Browser Team; community portable packaging
Homepage=https://github.com/zen-browser/desktop
Category=Internet
Description=Firefox-based web browser, repackaged for local portable use.
Language=Multilingual

[License]
Shareable=true
OpenSource=true
Freeware=true
CommercialUse=true

[Version]
PackageVersion=$numericVersion
DisplayVersion=$Version

[Control]
Icons=1
Start=ZenBrowserPortable.exe
"@
Set-Content -Path (Join-Path $appInfo 'appinfo.ini') -Value $appinfoText -Encoding ascii

$cs = Join-Path $repo 'builder\ZenBrowserPortable.cs'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
if (-not (Test-Path $compiler)) { throw 'Framework C# compiler missing on this Windows runner' }
if (-not (Test-Path $cs)) { throw "Missing launcher source file $cs" }
$launcher = Join-Path $package 'ZenBrowserPortable.exe'
$ico = Join-Path $appInfo 'appicon.ico'
& $compiler /nologo /target:winexe "/out:$launcher" "/win32icon:$ico" /reference:System.Windows.Forms.dll $cs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $launcher)) { throw 'Failed to compile Zen portable launcher' }

'All profile data and passwords belong here after first launch. Never upload this folder to GitHub; preserve it when updating. Avoid moving profiles across drive letters without testing.' | Set-Content (Join-Path $package 'Data\README.txt') -Encoding UTF8
# Shortcuts: always post-exit with target verification. Updater files: opt-in only.
foreach ($helper in @('ZenUpdateCleanup.ps1','Enable-Zen-Cleanup.cmd','Disable-Zen-Cleanup.cmd','CLEAN-ZEN-NOW.ps1','CLEAN-ZEN-NOW.cmd','Apply-Zen-Startup-Fix.ps1','APPLY-STARTUP-FIX.cmd')) {
    Copy-Item -LiteralPath (Join-Path $repo ('builder\' + $helper)) -Destination (Join-Path $package ('Other\' + $helper)) -Force
}
'Shortcut cleanup always runs on Zen exit and removes only verified links pointing to this portable installation. ProgramData updater cleanup is OFF by default and requires exact-folder approval via Other\Enable-Zen-Cleanup.cmd. Backups are stored inside Data; preserve Data on upgrades. See Other\README.txt.' | Set-Content (Join-Path $package 'Data\UpdaterCleanup\README.txt') -Encoding UTF8
@"
Zen Browser Portable - community ZIP build $Version ($Architecture)
Upstream https://github.com/zen-browser/desktop/releases/tag/$Version
Original installer SHA-256: $expectedHash
Launch ZenBrowserPortable.exe from this folder, NOT App\Zen\zen.exe.
Updates: close Zen completely; back up Data; replace App, Other and root launcher. Preserve Data.
ONE-CLICK USE: Just open ZenBrowserPortable.exe. It automatically checks startup preferences BEFORE Zen opens and runs the verified cleanup script AFTER Zen closes. No manual .cmd/PowerShell helper is needed for normal launches. Launcher events: Data\UpdaterCleanup\launcher.log. Removed items: Data\UpdaterCleanup\cleanup.log. These browser preferences are best-effort, not a guaranteed shortcut-creation block.
The ProgramData updater cleanup is OFF by default for a fresh installation. To opt in ONCE, close Zen, run Other\Enable-Zen-Cleanup.cmd, and paste the exact Update Folder from about:support. If upgrading with the existing Data folder, its previous approval remains and no setup is needed.
Once enabled, the root launcher also runs narrowly scoped ProgramData cleanup after Zen exits. It only touches the approved installation hash and recognized update files, backs them up under Data\UpdaterCleanup, and skips unknown data. No administrator elevation is attempted.
The helper also checks current-user Zen shortcut-state INI (after ProgramData opt-in), and removes empty updates and the approved Mozilla parent when empty only. It backs up every removed file. Shortcuts pointing to a different installation are preserved. Other Mozilla IDs and OS-managed traces are untouched. Unknown Mozilla parent contents are logged and preserved. To disable OPTIONAL ProgramData cleanup, run Other\Disable-Zen-Cleanup.cmd; safe shortcut cleanup remains active.
This package does not promise zero Windows-created traces, default-browser integration, or full portability of third-party extensions.
The built-in updater is intended to be disabled. Check security updates frequently and build a new ZIP promptly.
"@ | Set-Content (Join-Path $package 'Other\README.txt') -Encoding UTF8

$zip = Join-Path $out "ZenBrowser-$Version-$Architecture-Portable.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $package -DestinationPath $zip -CompressionLevel Optimal
python builder/verify_zip.py $zip
if ($LASTEXITCODE -ne 0) { throw 'Portable ZIP failed structural verification' }
Write-Host "Portable ZIP ready: $zip"
