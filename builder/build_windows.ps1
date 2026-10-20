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
New-Item -ItemType Directory -Path $targetApp, $appInfo, (Join-Path $package 'Data\Profile'), (Join-Path $package 'Data\Temp'), (Join-Path $package 'Data\HostEnvironment\Roaming'), (Join-Path $package 'Data\HostEnvironment\Local'), (Join-Path $package 'Data\UpdaterCleanup'), (Join-Path $package 'Other'), $out -Force | Out-Null

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
'{"policies":{"DisableAppUpdate":true,"DisableDefaultBrowserAgent":true,"DontCheckDefaultBrowser":true}}' | Set-Content -Path (Join-Path $distribution 'policies.json') -Encoding ascii

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
# Verify the Mozilla installation-hash routine on the Windows runner before packaging.
$hashTest = Join-Path $work 'hash-test.exe'
& $compiler /nologo /target:exe "/out:$hashTest" (Join-Path $repo 'builder\InstallHash.cs') (Join-Path $repo 'builder\hash_test.cs')
if ($LASTEXITCODE -ne 0) { throw 'Install hash test compilation failed' }
& $hashTest
if ($LASTEXITCODE -ne 0) { throw 'Mozilla CityHash64 install-hash reference vectors did not match' }
& $compiler /nologo /target:winexe "/out:$launcher" "/win32icon:$ico" /reference:System.Windows.Forms.dll $cs (Join-Path $repo 'builder\InstallHash.cs')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $launcher)) { throw 'Failed to compile Zen portable launcher' }

'All profile data and passwords belong here after first launch. Never upload this folder to GitHub; preserve it when updating. Browser settings are preserved; some Windows-bound sign-ins/passwords may require reauthentication.' | Set-Content (Join-Path $package 'Data\README.txt') -Encoding UTF8
# Shortcuts: verified target; updater: exact current install hash; registry: before/after guard.
foreach ($helper in @('ZenUpdateCleanup.ps1','ZenRegistryGuard.ps1','ZenProgramDataTracker.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repo ('builder\' + $helper)) -Destination (Join-Path $package ('Other\' + $helper)) -Force
}
@"
Automatic cleanup is run by ZenBrowserPortable.exe after exit. No activation or approval scripts.
It checks the calculated updater ID and tracks NEW per-session ProgramData folder + lock pairs.
All files removed are individually backed up. Unknown files and Thunderbird data are preserved.
HKCU\Software\Mozilla\Zen is snapshotted before launch and restored after exit.
Pre-existing keys remain present; host registry backup stays inside Data\HostEnvironment\Registry.
Manual overrides copied from older Data folders are ignored. See Other\README.txt.
"@ | Set-Content (Join-Path $package 'Data\UpdaterCleanup\README.txt') -Encoding UTF8
@"
Zen Browser Portable - cross-PC self-contained preview $Version ($Architecture)
Upstream https://github.com/zen-browser/desktop/releases/tag/$Version
Official installer SHA-256: $expectedHash

START: Double-click ZenBrowserPortable.exe, NEVER App\Zen\zen.exe.
First launch on a different PC: no updater approval or activation step.
The browser uses Data\Profile and child-only APPDATA/LOCALAPPDATA/TEMP redirection.
After browser shutdown it checks recognized, current-install updater files, verified shortcuts,
and restores the Zen-specific current-user registry branch to its pre-launch state.
A read-only per-session tracker checks newly created pairs if the cached/CityHash ID differs. Existing or ambiguous folders are preserved.
It never recursively removes Mozilla folders, never elevates, and always skips unfamiliar files.
Mozilla registry cached installation IDs are checked HKLM then HKCU before CityHash fallback.
If the ID still differs from Zen's internal ID, cleanup safely leaves uncertain files.
No elevated privileges, and no HKLM registry changes are made. Windows verification is essential.

UPDATE: preserve your existing Data folder. Replace root launcher, App and Other only.
Do not replace an existing Data folder with the blank Data from a new package.
Do not expect all website sessions or Windows-protected passwords to transfer across PCs.
Some Windows-created traces may remain; app-level cleanup is not forensic trace removal.
Launcher status: Data\UpdaterCleanup\launcher.log
Cleanup details: Data\UpdaterCleanup\cleanup.log
"@ | Set-Content (Join-Path $package 'Other\README.txt') -Encoding UTF8

$zip = Join-Path $out "ZenBrowser-$Version-$Architecture-Portable.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $package -DestinationPath $zip -CompressionLevel Optimal
python builder/verify_zip.py $zip
if ($LASTEXITCODE -ne 0) { throw 'Portable ZIP failed structural verification' }
Write-Host "Portable ZIP ready: $zip"
