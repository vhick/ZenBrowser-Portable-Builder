# Zen Browser Portable — one-click cross-PC preview

A standalone manually-run GitHub Actions Windows portable builder, based on the existing tested user installation. This is a **test candidate**, not independently validated on a clean Windows machine.

## What the build creates

```
ZenBrowserPortable/
  ZenBrowserPortable.exe     <- the only normal launcher
  App/                       <- replace for updates
    Zen/
    AppInfo/
  Data/                      <- NEVER replace on updates
    Profile/                 <- browser settings, bookmarks, extensions, history
    Temp/
    HostEnvironment/
      Roaming/
      Local/
    UpdaterCleanup/
  Other/
    ZenUpdateCleanup.ps1      <- automatic internal helper (no manual setup)
```

## How to build

1. Add this kit to your `ZenBrowser-Portable-Builder` GitHub repository, replacing previous files (delete old obsolete command helpers).
2. In GitHub Desktop, **Commit** and **Push origin**.
3. In GitHub, select **Actions → Build Zen Browser Portable ZIP (Manual) → Run workflow**.
4. Download the finished `ZenBrowser-...-Portable.zip` artifact and extract it.
5. **If updating an existing installation:** back up and KEEP your existing `Data` folder; copy only new `App`, `Other` and `ZenBrowserPortable.exe` into the existing portable directory. Never overwrite existing `Data`.
6. Double-click **ZenBrowserPortable.exe**. No manual updater approvals, TraceGuard or cleanup commands.

## What happens automatically

* Windows .NET launcher selects portable `Data\Profile` with `--no-remote --profile`.
* Only the Zen child process gets redirected `TEMP`, `TMP`, `APPDATA` and `LOCALAPPDATA` environment variables. These do **not** guarantee Windows Shell folder APIs will follow them.
* Portable browser policies disable self-update and the default-browser agent where Zen honors Firefox policies.
* After *all* `zen.exe` processes close, the launcher invokes targeted PowerShell cleanup without a prompt. The script validates the calculated Mozilla installation hash, checks the policy, validates shortcut targets, backs up each removed file, and never recursively deletes Mozilla directories.
* If the hash doesn't correspond to Zen's actual update root, the cleaner may **leave** updater files rather than guess a different hash. Inspect `Data\UpdaterCleanup\cleanup.log` if this happens.
* Unknown files and data owned by Thunderbird or another Zen installation are left untouched.

## Move to another Windows PC or after reinstalling Windows

Back up the **entire** `ZenBrowserPortable` folder before reinstalling Windows. Copy it to the new system and start `ZenBrowserPortable.exe`. Your portable profile is preserved. You may have to sign back into Zen Sync, websites, and extensions, and Windows-protected saved passwords may not decrypt on the new account.

## Important limitations

* This is **not a guarantee of zero Windows remnants**. Some browser code uses Windows APIs that bypass environment variables; crash handling, default-browser integration, registry state, filesystem junctions, and OS caches need validation. We intentionally do **not** delete registry keys or shared Mozilla files without proof of ownership.
* Portable startup might behave differently on a fresh Windows PC and must be tested there. The next validation step is a clean-Windows VM or second computer, with Thunderbird installed as a noninterference check, using TraceGuard only for that one-time engineering test.
* The portable profile may include private data. Don't share your `Data` folder publicly or upload it into GitHub.
* Zen built-in update is disabled; rebuild from the official releases promptly for security updates.

## Technical checks and sources

* The builder fetches the chosen official Zen tag, verifies release SHA-256, extracts official binaries, and reuses the official icon.
* Microsoft .NET Framework 4.x C# launcher compiles on GitHub's Windows runner.
* The builder compiles and runs a CityHash64 self-test before compiling the launcher. CityHash matches Google public reference vectors.
* Mozilla `GetInstallHash` hashes the resolved install directory using CityHash64 over UTF-16LE bytes. Cached `TaskBarIDs` entries matching the *exact installation path* are honored.
* The calculated installation path may not precisely match Mozilla's resolved junction/casing or an old cached hash. In these cases, cleanup is deliberately conservative.
* Sources: https://github.com/HasNetwork/zen-browser-portable, https://github.com/google/cityhash, https://firefox-admin-docs.mozilla.org/reference/policies/disableappupdate/, https://raw.githubusercontent.com/mozilla-firefox/firefox/main/toolkit/xre/nsXREDirProvider.cpp
