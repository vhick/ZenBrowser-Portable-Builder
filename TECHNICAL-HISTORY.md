

# Zen Browser Portable Builder (Windows)

A **manually triggered** GitHub Actions builder that downloads the **official Zen Browser Windows installer**, verifies the SHA-256 digest published by GitHub, extracts the official app without installing it, and creates a portable ZIP with `App / Data / Other / ZenBrowserPortable.exe` layout.

This is a **community packaging project**, not an official Zen Browser or PortableApps.com distribution. **This builder kit is not Zen Browser itself.** The original ZIP builder has been run on Windows; **this new shortcut prevention and cleanup update still needs a real Windows test**.

## START HERE — GitHub Desktop, no coding

1. At https://github.com/new, create an **empty** public repository named `ZenBrowser-Portable-Builder`. Do not add a README, .gitignore or license there.
2. Download the builder kit ZIP and **Extract All** on Windows.
3. Open your working **GitHub Desktop** → **File → Clone repository** → select the new `ZenBrowser-Portable-Builder` repository and clone it.
4. In GitHub Desktop, click **Repository → Show in Explorer**.
5. From the *extracted builder kit folder*, copy `.github`, `builder`, `tests`, `.gitignore`, `README.md`, and `START-HERE.txt` **into the cloned repository folder**. Make sure `.github/workflows/build-zen-browser-portable.yml` is preserved. Do not upload the ZIP as one file.
6. Return to GitHub Desktop → type `Add Zen portable builder` for the commit summary → **Commit to main** → **Push origin**.
7. Open your repository on GitHub.com → **Actions** → **Build Zen Browser Portable ZIP (Manual)** → **Run workflow**. Choose branch `main`, stable release `1.23.3b`, and `x64` for ordinary Intel/AMD Windows PCs. Choose `arm64` only if your Windows PC has an ARM processor.
8. Start a **new run**. After it finishes with a green checkmark, open the run → **Artifacts** → download `ZenBrowser-Portable-1.23.3b-x64` (or ARM64). Extract the downloaded GitHub wrapper ZIP. Extract `ZenBrowser-1.23.3b-x64-Portable.zip` inside it.
9. Open the extracted `ZenBrowserPortable` folder and **launch `ZenBrowserPortable.exe`**, never the inner `App/Zen/zen.exe` directly.

The workflow requires no copy of the Zen source repository and does not build Firefox from source. It uses official published Windows installer binaries and a small community launcher. The ZIP artifact is retained for **7 days** (change `retention-days` if desired).

## Expected application folder

```text
ZenBrowserPortable/
  ZenBrowserPortable.exe             <- launch this
  App/
    Zen/
      zen.exe
      xul.dll
      omni.ja
      browser/ ...
      distribution/policies.json      <- disables in-app updates (Firefox-compatible policy)
    AppInfo/
      appinfo.ini                    <- PortableApps Menu name and category
      appicon.ico                    <- original multi-resolution Zen icon
      appicon_16.png
      appicon_32.png
      appicon_75.png
      appicon_128.png
      appicon_256.png
  Data/
    Profile/                         <- bookmarks, extensions, browsing history, preferences, sessions
    Temp/                            <- local temporary files
    UpdaterCleanup/                  <- opt-in cleanup config, backups and log
    README.txt
  Other/
    APPLY-STARTUP-FIX.cmd              <- one-time migration helper for older installations
    Apply-Zen-Startup-Fix.ps1
    ZenUpdateCleanup.ps1             <- conservatively cleans approved updater files
    Enable-Zen-Cleanup.cmd           <- optional one-time setup (manual)
    Disable-Zen-Cleanup.cmd          <- disable cleanup at any time
    README.txt
```

`ZenBrowserPortable.exe` launches `App/Zen/zen.exe --no-remote --profile <full path to Data/Profile>` and sets `TEMP/TMP` for that process. On initial use it creates `Data/Profile/user.js` with starter preferences including default-browser checks and application updates disabled. **It applies best-effort shortcut-prevention preferences to Data/Profile/user.js before each start, including on existing profiles. `browser.shell.customIcon.enabled=false` and `browser.privacySegmentation.enabled=false` do not disable the ability to use a Private Window, but can affect separate taskbar icons. Recent Mozilla versions may ignore these preferences for shortcut creation. It does not register itself as your Windows default browser.** Zen may still leave some OS-managed traces or data from third-party extensions.

## Safe Start Menu shortcut cleanup (always on); ProgramData cleanup (opt-in)

The main browser profile stays under `Data/Profile`. The system-level Mozilla updater is separate from the profile, and can still write to `C:\ProgramData\Mozilla-...` despite a functioning `DisableAppUpdate` enterprise policy. Start Menu shortcuts verified to point into this portable Zen installation are cleaned automatically on exit, whether or not you approve updater cleanup. Separately, optional ProgramData cleanup handles **only the exact Zen Update Folder you personally approve**; neither method prevents every Windows file from appearing while Zen runs.

**Enable the cleanup only if you have verified the updater folder belongs to the portable Zen copy.** You already identified this exact Update Folder in `about:support` on one PC:

`C:\ProgramData\Mozilla-1de4eec8-1241-4177-a864-e594e8d1fb38\updates\635D1EFBEDD005D5`

**After building and extracting the NEW portable ZIP:**

1. Exit all Zen windows completely. **Back up your existing `Data` directory.**
2. Replace only **`App`**, the root **`ZenBrowserPortable.exe`**, and **`Other`** from the new ZIP. Keep the complete original **`Data`** directory intact.
3. Open `ZenBrowserPortable/Other/Enable-Zen-Cleanup.cmd` (double-click).
4. When prompted, paste the exact **Update Folder path**, or the full path to its `update-config.json` file. The helper checks that it matches a strict Windows ProgramData / Mozilla / 16-character installation ID pattern. If its folder was already deleted, an existing matching zero-byte UpdateLock may be used for approval. Type **`APPROVE`** when requested.
5. Open **the root `ZenBrowserPortable.exe`** as normal. On closing Zen, the launcher always checks verified shortcuts and also attempts updater cleanup for the exact previously approved folder, if configured.
6. Review `Data/UpdaterCleanup/cleanup.log`. Copies of recognized files are saved inside `Data/UpdaterCleanup/Backups/` before deletion.

**What can be removed:** the approved installation hash's `update-config.json`, `parent.lock`, matching zero-byte `UpdateLock-<approved ID>`, empty updater subdirectories and empty Windows `AppData/zen` directories. Also checked are the two specific current-user Start Menu links (even without updater approval), the matching current-user `Zen_<SID>_shortcuts.ini` (only with updater approval), and the parent `updates` directory, plus the approved `Mozilla-{GUID}` directory. Both parent directories are removed ONLY when completely empty; if not, remaining item names are logged. Shortcuts are removed only when their TargetPath matches this portable installation. All removed files are backed up in `Data/UpdaterCleanup/Backups`.

**What will NOT be deleted:** other Mozilla update hashes, a nonempty `C:\ProgramData\Mozilla-*` root, active update downloads, unknown/new files, nonempty AppData folders, symbolic links/junctions, links pointing to another installed Zen, other users' shortcut INIs, or data belonging to other Firefox-family installations. If unknown content exists in the approved updater folder, the script *skips deletion of that folder and its unknown contents*. If ordinary permissions prevent removal, it logs the error; it does not request Administrator rights.

The **ProgramData updater cleanup** is optional. To turn updater cleanup off, double-click `Other/Disable-Zen-Cleanup.cmd`, or delete `Data/UpdaterCleanup/approved-update-folder.txt`. The target-verified Start Menu shortcut cleanup will stay active. **Do not upload your configured `Data` folder to GitHub.**

**Important:** This is a post-exit cleanup attempt, not proof of a completely remnant-free browser. Any program can create other Windows traces, and the updater may initialize files while Zen is running. Future releases can change the layout: if the live Update Folder changes in `about:support`, repeat approval for that new *verified* path. Do not blindly approve older/different hashes.

### Why use the official installer instead of an official ZIP?

The Zen Browser 1.23.3b release publishes `zen.installer.exe` (or `zen.installer-arm64.exe`), which contains a `core` directory when extracted with 7-Zip. Scoop's Zen Browser package also uses this approach. The builder **extracts** it; it never executes it on the GitHub Actions runner.

The action retrieves the selected release through the GitHub Releases API and **requires the asset's official `sha256:` digest**. If the checksum is unavailable or wrong, it stops. The original application icon is extracted from the official Zen `zen.exe` as a full multi-resolution ICO, not substituted with generic artwork. The root launcher is compiled using that same ICO. A browser with missing essential files fails validation before upload.

## How to update

1. Check the official releases: https://github.com/zen-browser/desktop/releases/latest. Keep up with security fixes; disabling automatic updates means **you** must regularly build the newest stable release.
2. In your builder repo, run the **manual** workflow again and enter the new stable release tag (no `v` if the official tag has no `v`).
3. When a build succeeds, close all running Zen windows and background processes.
4. **Back up the entire existing `Data` folder.**
5. In your existing portable application folder, **replace `App`, `Other`, and `ZenBrowserPortable.exe`** from the new ZIP. **Always preserve `Data`** and do not merge the new empty Data folder over the old one. The new cleanup helper lives in `Other`.
6. Open `ZenBrowserPortable.exe` and check Settings, extensions, bookmarks, logins and `about:profiles`.

**Do not downgrade the browser binary while reusing a profile created by a newer version.** Some Zen/Firefox profile files include **absolute paths** (e.g. extension locations), so a Windows reinstall or move to another drive letter may require extension reinstall or profile repair. Reinstalling Windows may also require logging in again.

## First Windows portability tests

1. Launch `ZenBrowserPortable.exe` from an extracted, writable folder.
2. In the browser, open `about:profiles` and verify the active **Root Directory** is under `ZenBrowserPortable\Data\Profile`.
3. Change settings; add a bookmark; install one extension. Exit all browser processes. Relaunch the root launcher; make sure changes persist.
4. Check for new files in `%APPDATA%\zen` and `%LOCALAPPDATA%\zen`, and check whether changing the Windows default browser was requested. Do **not** delete existing system profiles.
5. Test updates as above, retaining `Data`.
6. If you move the portable folder between drives, confirm profile operation and inspect extensions. Some extensions may retain old absolute paths.

**Portability scope:** The builder directs the main Zen profile and temporary files into `Data`. It cannot guarantee that OS-created traces, third-party extension caches, Windows file associations, or protected storage keys never use the host system.

## Security and permissions

- Never add your live browser `Data`, passwords, cookies, or session files to the builder repository or GitHub Actions artifacts. A `.gitignore` file excludes common sensitive profile files and folders.
- For security, only use new stable releases downloaded from official Zen GitHub releases. The builder verifies the published SHA-256 checksum and refuses missing or mismatched digests.
- Automatic in-app updates are intended to be disabled through Firefox-compatible policy and profile preferences. Whether Zen honors the policy in every future version needs Windows verification. Build browser security releases promptly.
- `ZenBrowserPortable.exe` uses the .NET Framework compiler available on Windows runners. It is a community launcher, *not* the official PortableApps.com Launcher. The ZIP is PortableApps Menu-compatible but it does **not** produce a `.paf.exe` installer.
- MPL-2.0 is the source repository's declared license. Binary redistribution and third-party license obligations should be reviewed before publishing redistributable builds.

## References

- Zen official repo: https://github.com/zen-browser/desktop
- Official release: https://github.com/zen-browser/desktop/releases/tag/1.23.3b
- Official 1.23.3b asset list / checksums: https://github.com/zen-browser/desktop/releases/expanded_assets/1.23.3b
- Scoop Zen extraction example: https://github.com/ScoopInstaller/Extras/blob/master/bucket/zen-browser.json
- Firefox command-line options: https://github.com/mozilla-firefox/firefox/blob/main/browser/docs/CommandLineParameters.md
- PortableApps.com Format: https://portableapps.com/development/portableapps.com_format

Questions or a failed Action? In GitHub, open the run, click the red failed step, and download **View raw logs / Download log archive**, then attach the log to our chat.


## 2026-10-19 update: orphaned UpdateLock-only case

The previous script accidentally skipped an approved `UpdateLock-<installation-hash>` whenever its sibling `updates/<installation-hash>` directory was absent. Mozilla's Firefox-family update-sync manager can leave that zero-byte lock behind even when updates are disabled. The new `builder/ZenUpdateCleanup.ps1` handles the exact already-approved hash even if the update directory is gone. Other installation IDs are never deleted. The exact approved Mozilla parent can now be deleted only if empty, after scoped cleanup.

**Apply:** Replace only `builder/ZenUpdateCleanup.ps1` in your GitHub builder, commit and push, then start a new manual build. The fresh artifact includes the updated cleanup script under `Other/ZenUpdateCleanup.ps1`. After closing Zen, preserve the existing `Data` folder, replace `App`, `Other`, and `ZenBrowserPortable.exe` from the new ZIP. If cleanup is not already enabled, run `Other/Enable-Zen-Cleanup.cmd` and enter the exact update folder shown by `about:support`, not the name of the lock. Approval now allows a missing update folder **only if its matching zero-byte lock exists**. To confirm configuration, check `Data/UpdaterCleanup/approved-update-folder.txt`; after a normal shutdown read `Data/UpdaterCleanup/cleanup.log`.

The first-launch `Zen.lnk` and `{-brand-shortcut-name} Private Browsing.lnk` may be first-run integration side effects. The revised cleaner checks those exact filenames, and deletes them only if their shortcut target is this portable copy. The empty AppData Zen folders are removed when empty as part of approved cleanup, but may exist while the browser is running. **No changes to application updater binaries are made; this remains post-exit cleanup rather than preventing writes.**

**Do not delete `C:\ProgramData\Mozilla-...` recursively.** Other Firefox-family applications can use that shared root. This build and its new tests were not executed on a Windows device here.

## 2026-10-19 follow-up: four named Windows remnants

The follow-up cleanup handles the user-reported `Zen.lnk`, the literal malformed
`{-brand-shortcut-name} Private Browsing.lnk`, the **empty** parent Mozilla `updates` folder,
and the exact current Windows user `Zen_<SID>_shortcuts.ini` under the already approved Mozilla root.
It reports `Not present`, `Removed`, `RETAINED`, or `SKIP` for each location.
Files are copied into portable `Data/UpdaterCleanup/Backups` before removal.
No administrator privileges, recursive removal, or deletion of profiles/other installations.
A shortcut to a separately installed Zen is preserved, even if named `Zen.lnk`.
The shortcut-state INI is skipped if it explicitly refers to another installed `zen.exe`.
Portable cleanup cannot prevent all OS side effects while Zen runs.

## 2026-10-19 latest: private-browsing shortcut and empty parent

The October 19 cleanup log revealed that the malformed Start Menu private shortcut targeted `App/Zen/private_browsing.exe` inside this portable installation. The previous target allowlist did not include the Firefox-family private launcher. The updated cleanup recognizes this one exact additional target and backs up the shortcut before removal. A shortcut targeting any other installation remains untouched.

After clearing the approved update hash, the script now also checks its exact `C:\ProgramData\Mozilla-{GUID}` parent. If that directory is **empty**, it removes the directory without using recursive deletion. If not empty (including hidden files), it leaves everything untouched and logs the names of the remaining items; permission errors are logged. **No automatic blanket Mozilla-directory deletion.**

To update an existing portable app, extract the *small cleanup fix* over the current folder, replacing only files in `Other`. Keep your `Data`, `App`, and root executable unchanged. Run `Other/CLEAN-ZEN-NOW.cmd` with Zen closed, and check `Data/UpdaterCleanup/cleanup.log`. No GitHub rebuild is required for this small fix.


## October 2026: Private Browsing shortcut prevention update

Mozilla confirmed that browser startup can create Start Menu shortcuts despite
installer flags, and newer builds can do so despite `browser.shell.customIcon.enabled=false`.
The updater installer switch `/PrivateBrowsingShortcut=false` cannot control an
extracted Zen browser once it is already launching.

The **new root launcher** applies `browser.shell.customIcon.enabled=false` and
`browser.privacySegmentation.enabled=false` inside `Data/Profile/user.js` *before*
launch, for new and existing profiles. It backs up existing `user.js` before changing it.
These are best-effort settings and do not disable opening private windows.

After Zen closes, the launcher **always** invokes `Other/ZenUpdateCleanup.ps1` to check
only the named Start Menu shortcuts. A shortcut is removed only when its target
points to `ZenBrowserPortable.exe`, `App/Zen/zen.exe`, or
`App/Zen/private_browsing.exe` in this **same** portable folder.
Automatic updater/ProgramData cleanup is still **off until explicitly approved**.

For an **existing** ZenBrowserPortable.exe built before this change, use the
small patch ZIP and run `Other/APPLY-STARTUP-FIX.cmd` once while Zen is closed.
The older launcher will run cleanup automatically only when updater cleanup
was approved earlier; `Other/CLEAN-ZEN-NOW.cmd` can clean the specific shortcuts
even without updater approval. To receive automatic non-opt-in shortcut cleanup,
rebuild and replace the root `ZenBrowserPortable.exe` from the new builder.

Do not replace `Data` during updates. Tested with static automated checks in this
kit; **not verified against a live Windows Zen process in this environment**.
