# Zen Browser Portable — Final One-Click Builder

This is a **GitHub Actions build kit**, not the Zen browser application. Running its **manual** GitHub Action creates a downloadable complete `ZenBrowserPortable` application ZIP. It uses official Zen release binaries and the original official Zen icon.

## Normal use: only one executable

After building the application, **double-click `ZenBrowserPortable.exe`**. Don't open the helper `.cmd`/`.ps1` scripts before starting Zen. Don't launch `App\Zen\zen.exe` directly.

The root launcher automatically:

1. Applies shortcut-prevention settings **before** the browser starts, preserving and backing up an existing `Data\Profile\user.js` when it changes.
2. Launches Zen with the saved browser profile under `Data\Profile` and temporary files under `Data\Temp`.
3. Waits until the main Zen process has closed. The cleanup helper checks for any remaining `zen.exe` processes before touching host files.
4. Runs `Other\ZenUpdateCleanup.ps1` silently after exit. It backs up and removes only verified Start Menu links that belong to this portable Zen. If updater cleanup was already approved, it also removes only the approved updater remnants.
5. Writes `Data\UpdaterCleanup\launcher.log` (automation record) and `Data\UpdaterCleanup\cleanup.log` (individual cleanup results).

**Previously approved updater folder:** Approval is stored in your existing `Data\UpdaterCleanup\approved-update-folder.txt`. **Keep your current Data folder** on upgrades to retain that approval and all browser settings; then there are **no manual scripts to run at every launch**.

**Exception for a fresh Windows setup:** If you have never opted into the optional system-level updater cleanup, it remains **off** for safety. To enable it on that Windows installation, close Zen and use `Other\Enable-Zen-Cleanup.cmd` *once*, entering the exact Zen Update Folder from `about:support`. Shortcut cleanup does **not** require this approval. No extra helper needs to be run during normal use.

## Build the real portable ZIP on GitHub

1. Extract **this builder ZIP** on your computer.
2. Open your **existing Zen Portable builder repository** with GitHub Desktop (or create an empty repository if needed).
3. In GitHub Desktop choose **Repository → Show in Explorer**. Copy all contents of the extracted kit into your local repository, including the hidden `.github` folder. Allow files to replace older builder files.
4. In GitHub Desktop choose **Commit to main → Push origin**.
5. Open GitHub.com → your repository → **Actions → Build Zen Browser Portable ZIP (Manual) → Run workflow**. Keep `1.23.3b` and `x64` for a standard Windows Intel/AMD PC, unless selecting a newer official stable tag.
6. After a green successful run, download the **Artifacts** ZIP, extract it, and then extract the inner `ZenBrowser-<version>-x64-Portable.zip` to get the actual portable application.
7. Open `ZenBrowserPortable\ZenBrowserPortable.exe`. You need no `.cmd` file or PowerShell window for ordinary use.

You can build new Zen versions manually in GitHub Actions. The action does **not** automatically sync the upstream repository or build portable artifacts on a schedule. It verifies the official Windows installer against the SHA-256 checksum published on the official GitHub release before extraction.

## Upgrade without losing your settings

1. Close all Zen windows and processes.
2. Make a backup of your existing `ZenBrowserPortable\Data` folder.
3. Extract the newly built portable ZIP separately.
4. In your existing portable installation, replace **only** `App`, `Other`, and the root `ZenBrowserPortable.exe` with the files from the newly built package.
5. **Do not overwrite, replace, or delete `Data`.** It contains your profile, settings, extensions, bookmarks, logins, and previous updater-cleanup approval.
6. Double-click `ZenBrowserPortable.exe` as usual.

Do not use an older Zen binary with a profile that was upgraded by a newer Zen version.

## Structure of actual app ZIP

```text
ZenBrowserPortable/
├─ ZenBrowserPortable.exe       ← the ONE shortcut/launcher to use
├─ App/
│  ├─ Zen/                      ← official Zen browser program files
│  └─ AppInfo/                  ← original icon and PortableApps metadata
├─ Data/
│  ├─ Profile/                  ← keep on every upgrade
│  ├─ Temp/
│  └─ UpdaterCleanup/          ← approval, logs, file backups
└─ Other/                       ← helpers auto-run by the root launcher
```

## Limits and safeguards

This is a **community-built Windows portable ZIP**, not an official Zen or `.paf.exe` package. The launcher is generated on the Windows GitHub Actions runner. The builder has offline tests, but a new compiled launcher must still be run and verified on a real Windows PC. Firefox-derived Windows integration may still create files *while Zen runs*; the cleaner removes only verified known remnants *after Zen closes*. It does not promise zero Windows traces, and it does not recursively erase shared Mozilla ProgramData folders, delete other installations' links, or elevate privileges.

Official releases: https://github.com/zen-browser/desktop/releases
Zen project: https://github.com/zen-browser/desktop

For historical troubleshooting notes, see `TECHNICAL-HISTORY.md`.
