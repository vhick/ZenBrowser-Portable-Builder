import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('verify_zip', ROOT/'builder'/'verify_zip.py')
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)

REQUIRED = [
    'ZenBrowserPortable.exe', 'App/Zen/zen.exe', 'App/Zen/omni.ja',
    'App/Zen/xul.dll', 'App/Zen/distribution/policies.json',
    'App/Zen/browser/chrome.manifest', 'App/AppInfo/appinfo.ini',
    'App/AppInfo/appicon.ico', 'Other/README.txt',
    'Other/ZenUpdateCleanup.ps1', 'Other/Enable-Zen-Cleanup.cmd',
    'Other/Disable-Zen-Cleanup.cmd',
    'Other/Apply-Zen-Startup-Fix.ps1', 'Other/APPLY-STARTUP-FIX.cmd',
] + [f'App/AppInfo/appicon_{size}.png' for size in (16, 32, 75, 128, 256)]

class BuilderTests(unittest.TestCase):
    def create_zip(self, dirname, files):
        path = Path(dirname) / 'test.zip'
        with zipfile.ZipFile(path, 'w') as z:
            for relative in files:
                z.writestr('ZenBrowserPortable/' + relative, 'sample')
        return path

    def test_clean_package_structure(self):
        with tempfile.TemporaryDirectory() as t:
            self.assertTrue(VERIFY.verify(self.create_zip(t, REQUIRED)))

    def test_reject_missing_launcher(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(RuntimeError, 'Missing'):
                VERIFY.verify(self.create_zip(t, [f for f in REQUIRED if f != 'ZenBrowserPortable.exe']))

    def test_reject_missing_browser_dll(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(RuntimeError, 'Missing'):
                VERIFY.verify(self.create_zip(t, [f for f in REQUIRED if f != 'App/Zen/xul.dll']))

    def test_reject_profile_in_package(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(RuntimeError, 'profile'):
                VERIFY.verify(self.create_zip(t, REQUIRED + ['Data/Profile/logins.json']))

    def test_reject_profile_in_package_case(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(RuntimeError, 'profile'):
                VERIFY.verify(self.create_zip(t, REQUIRED + ['Data/Profile/prefs.js']))

    def test_require_browser_assets(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(RuntimeError, 'browser assets'):
                VERIFY.verify(self.create_zip(t, [f for f in REQUIRED if not f.startswith('App/Zen/browser/')]))

    def test_reject_machine_specific_cleanup_approval(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(RuntimeError, 'machine-specific'):
                VERIFY.verify(self.create_zip(t, REQUIRED + ['Data/UpdaterCleanup/approved-update-folder.txt']))

    def test_cleanup_default_disabled(self):
        text = (ROOT / 'builder/ZenBrowserPortable.cs').read_text(encoding='utf-8')
        self.assertIn('if (!File.Exists(script))', text)
        self.assertNotIn('File.Exists(config)', text)
        self.assertIn('TryPostExitCleanup(root)', text)
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8')
        self.assertIn("Log 'Updater cleanup is OFF (no approved folder). Verified shortcut cleanup finished.'", script)
        self.assertIn('DisableAppUpdate', script)


    def test_unapproved_cleanup_scoped_to_shortcuts(self):
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8-sig')
        clean_branch = script.split("} else {\n    # Safe shortcut cleanup works", 1)[1]
        self.assertLess(clean_branch.index('Clean-Portable-StartMenu-Shortcuts'), clean_branch.index('Test-Path -LiteralPath $configPath'))
        self.assertIn('Clean-Approved $approved', clean_branch)
        self.assertNotIn('Clean-Approved $approved', clean_branch.split('configPath',1)[0])

    def test_profile_preferences_applied_before_browser_launch(self):
        launcher = (ROOT / 'builder/ZenBrowserPortable.cs').read_text(encoding='utf-8')
        self.assertIn('browser.shell.customIcon.enabled', launcher)
        self.assertIn('browser.privacySegmentation.enabled', launcher)
        self.assertLess(launcher.index('EnsurePortablePreferences(root, profile);'), launcher.index('using (Process child = Process.Start(psi))'))
        self.assertIn('File.Copy(userJs, dest, false);', launcher)
        self.assertIn('File.WriteAllText(userJs, contents', launcher)
        self.assertNotIn('DisablePrivateBrowsing', launcher)
        self.assertNotIn('browser.privacySegmentation.createdShortcut', launcher)

    def test_existing_installation_standalone_patch(self):
        script = (ROOT / 'builder/Apply-Zen-Startup-Fix.ps1').read_text(encoding='utf-8')
        self.assertIn('App\\Zen\\zen.exe', script)
        self.assertIn('Data\\Profile', script)
        self.assertIn('Get-Process -Name zen', script)
        self.assertIn('Copy-Item -LiteralPath $userJs', script)
        self.assertIn('browser.shell.customIcon.enabled', script)
        self.assertIn('browser.privacySegmentation.enabled', script)
        self.assertNotIn('Remove-Item -Recurse', script)
        ps = (ROOT / 'builder/build_windows.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('APPLY-STARTUP-FIX.cmd', ps)
        self.assertIn('Apply-Zen-Startup-Fix.ps1', ps)

    def test_cleanup_requires_exact_user_approved_path(self):
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8')
        self.assertIn('approved-update-folder.txt', script)
        self.assertIn("ValidateSet('Configure','Clean','Check')", script)
        self.assertIn("'APPROVE'", script)
        self.assertIn('guid]::TryParse', script)
        self.assertIn('ProgramData', script)
        self.assertIn('ReparsePoint', script)

    def test_cleanup_skips_shared_or_unknown_data(self):
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8')
        self.assertIn('No-Zen-Processes', script)
        self.assertIn('SKIP: unknown folder', script)
        self.assertIn('SKIP: update files or unfamiliar directories exist', script)
        self.assertIn("$allowFiles = @('update-config.json','parent.lock')", script)
        self.assertIn('Backups', script)
        self.assertNotIn('Remove-Item -Recurse', script)
        self.assertNotIn('Remove-Item -Path $mozillaRoot', script)

    def test_four_exact_remnants_have_safe_checks(self):
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("'Zen.lnk'", script)
        self.assertIn("'{-brand-shortcut-name} Private Browsing.lnk'", script)
        self.assertIn('Test-PortableShortcut', script)
        self.assertIn('Clean-Portable-StartMenu-Shortcuts', script)
        self.assertIn('Clean-Approved-Zen-Shortcut-State', script)
        self.assertIn('shortcut belongs to a different target', script)
        self.assertIn("'Zen_' + $sid + '_shortcuts.ini'", script)
        self.assertIn('mentions another Zen installation', script)
        self.assertIn('Report-And-Prune-Empty-MozillaUpdates', script)
        self.assertIn('shared Mozilla updates directory is not empty', script)
        self.assertIn('Save-And-Remove-Exact', script)
        self.assertNotIn('Remove-Item -Recurse', script)

    def test_private_shortcut_portable_executable_is_supported(self):
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("'App\\Zen\\private_browsing.exe'", script)
        self.assertIn('$actual -ieq $privateExe', script)
        self.assertIn('Save-And-Remove-Exact', script)
        self.assertIn('Test-NoLinkedAncestors', script)

    def test_only_empty_approved_mozilla_parent_can_be_removed(self):
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8-sig')
        branch = script.split('function Report-And-Prune-Empty-MozillaRoot', 1)[1].split('function Clean-Approved', 1)[0]
        self.assertIn('Test-NoLinkedAncestors $mozillaRoot $env:ProgramData', branch)
        self.assertIn('Get-ChildItem -LiteralPath $mozillaRoot -Force', branch)
        self.assertIn('if ($remaining.Count -gt 0)', branch)
        self.assertIn('RETAINED: Mozilla parent contains', branch)
        self.assertIn('No-Zen-Processes', branch)
        self.assertIn('Remove-Item -LiteralPath $mozillaRoot -Force -ErrorAction Stop', branch)
        self.assertNotIn('-Recurse', branch.split('Remove-Item -LiteralPath $mozillaRoot')[1].split('\n')[0])
        self.assertEqual(script.count('Report-And-Prune-Empty-MozillaRoot $mozillaRoot'), 2)

    def test_lock_is_handled_when_approved_update_folder_is_absent(self):
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8')
        branch = script.split('if (-not (Test-Path -LiteralPath $folder -PathType Container)) {', 1)[1]
        branch = branch.split("  $allowFiles = @('update-config.json','parent.lock')", 1)[0]
        self.assertIn('UpdateLock-', script)
        self.assertIn('Is-PlainFile $updateLock', branch)
        self.assertIn('Length -ne 0', branch)
        self.assertIn('Copy-Item -LiteralPath $updateLock', branch)
        self.assertIn('No-Zen-Processes', branch)
        self.assertIn('Remove-Item -LiteralPath $updateLock', branch)
        self.assertIn('Clean-Empty-Zen-AppData', branch)
        self.assertNotIn('Remove-Item -Recurse', branch)

    def test_cleanup_approval_handles_missing_directory_with_exact_lock(self):
        script = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8')
        self.assertIn('lockCandidate', script)
        self.assertIn('Is-PlainFile $lockCandidate', script)
        self.assertIn('Length -ne 0', script)
        self.assertIn('APPROVE', script)

    def test_cleanup_script_packaged_into_application(self):
        ps = (ROOT / 'builder/build_windows.ps1').read_text(encoding='utf-8')
        self.assertIn("'ZenUpdateCleanup.ps1','Enable-Zen-Cleanup.cmd','Disable-Zen-Cleanup.cmd'", ps)
        self.assertIn(r'Data\UpdaterCleanup', ps)

    def test_workflow_manual_only(self):
        txt = (ROOT / '.github/workflows/build-zen-browser-portable.yml').read_text(encoding='utf-8')
        self.assertIn('workflow_dispatch:', txt)
        self.assertNotIn('schedule:', txt)
        self.assertNotIn('push:', txt)
        self.assertNotIn('pull_request:', txt)

    def test_manual_workflow_has_no_shared_concurrency_lock(self):
        txt = (ROOT / '.github/workflows/build-zen-browser-portable.yml').read_text(encoding='utf-8')
        # A stuck/orphaned manual run must not block later runs using the same group.
        self.assertNotIn('concurrency:', txt)
        self.assertNotIn('zen-portable-manual', txt)

    def test_pinned_release_is_current_stable(self):
        txt = (ROOT / '.github/workflows/build-zen-browser-portable.yml').read_text(encoding='utf-8')
        self.assertIn("default: '1.23.3b'", txt)

    def test_official_asset_sha_verification(self):
        txt = (ROOT / 'builder/build_windows.ps1').read_text(encoding='utf-8')
        self.assertIn('api.github.com/repos/zen-browser/desktop/releases/tags/', txt)
        self.assertIn("$asset.digest -notmatch '^sha256:", txt)
        self.assertIn('$actualHash -ne $expectedHash', txt)

    def test_extraction_requires_complete_browser(self):
        txt = (ROOT / 'builder/build_windows.ps1').read_text(encoding='utf-8')
        self.assertIn("@('zen.exe','omni.ja','xul.dll')", txt)
        self.assertIn("$extract 'core'", txt)

    def test_launcher_uses_portable_profile(self):
        txt = (ROOT/'builder/ZenBrowserPortable.cs').read_text(encoding='utf-8')
        self.assertIn('Data\\Profile', txt)
        self.assertIn('--no-remote --profile', txt)
        self.assertIn('TEMP', txt)
        self.assertNotIn('Registry.', txt)

    def test_upgrades_preserve_data(self):
        txt = (ROOT/'README.md').read_text(encoding='utf-8')
        self.assertIn('Do not overwrite, replace, or delete `Data`', txt)
        self.assertIn('replace **only** `App`, `Other`', txt)

    def test_original_multires_icon(self):
        txt = (ROOT/'builder/create_icons.py').read_text(encoding='utf-8')
        self.assertIn('IconExtractor', txt)
        self.assertIn('export_icon', txt)
        self.assertIn('(16, 32, 75, 128, 256)', txt)

    def test_in_app_updates_intended_off(self):
        txt = (ROOT/'builder/build_windows.ps1').read_text(encoding='utf-8')
        self.assertIn('DisableAppUpdate', txt)
        self.assertIn('DontCheckDefaultBrowser', txt)


    def test_one_click_launcher_performs_start_and_cleanup(self):
        launcher = (ROOT / 'builder/ZenBrowserPortable.cs').read_text(encoding='utf-8')
        self.assertIn('EnsurePortablePreferences(root, profile);', launcher)
        self.assertIn('TryPostExitCleanup(root);', launcher)
        self.assertLess(launcher.index('EnsurePortablePreferences(root, profile);'), launcher.index('using (Process child = Process.Start(psi))'))
        self.assertGreater(launcher.index('TryPostExitCleanup(root);'), launcher.index('child.WaitForExit();'))
        self.assertIn('finally', launcher)
        self.assertIn('launcher.log', launcher)
        self.assertIn('Automatic post-exit cleanup started.', launcher)

    def test_launcher_waits_for_every_zen_process_before_cleanup(self):
        launcher = (ROOT / 'builder/ZenBrowserPortable.cs').read_text(encoding='utf-8')
        self.assertIn('Process.GetProcessesByName("zen")', launcher)
        self.assertIn('quietChecks < 5', launcher)
        self.assertIn('if (WaitForZenShutdown(root)) TryPostExitCleanup(root);', launcher)
        self.assertLess(launcher.index('child.WaitForExit();'),
                        launcher.rindex('if (WaitForZenShutdown(root)) TryPostExitCleanup(root);'))
        self.assertIn('All zen.exe processes closed and remained absent', launcher)

    def test_launcher_does_not_end_browser_processes(self):
        launcher = (ROOT / 'builder/ZenBrowserPortable.cs').read_text(encoding='utf-8')
        shutdown = launcher.split('private static bool WaitForZenShutdown', 1)[1].split('private static void EnsurePortablePreferences', 1)[0]
        self.assertNotIn('.Kill()', shutdown)
        self.assertNotIn('TerminateProcess', shutdown)
        self.assertIn('return false;', shutdown)

    def test_no_automatic_programdata_deletion_without_exact_approval(self):
        cleanup = (ROOT / 'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("Log 'Updater cleanup is OFF (no approved folder). Verified shortcut cleanup finished.'", cleanup)
        self.assertIn('Clean-Portable-StartMenu-Shortcuts', cleanup)
        self.assertNotIn('Remove-Item -Recurse', cleanup)
        self.assertIn('approved-update-folder.txt', cleanup)

    def test_package_documents_no_scripts_needed_for_normal_use(self):
        intro = (ROOT / 'ONE-CLICK-START-HERE.txt').read_text(encoding='utf-8')
        self.assertIn('Just double-click ZenBrowserPortable.exe', intro)
        self.assertIn('preserve your existing Data folder', (ROOT / 'START-HERE.txt').read_text(encoding='utf-8'))

if __name__ == '__main__':
    unittest.main()
