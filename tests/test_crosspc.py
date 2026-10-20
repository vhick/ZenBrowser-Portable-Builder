from pathlib import Path
import zipfile
import tempfile
import importlib.util
import unittest
ROOT=Path(__file__).resolve().parents[1]

class CrossPcBuilderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.launch=(ROOT/'builder/ZenBrowserPortable.cs').read_text()
        cls.clean=(ROOT/'builder/ZenUpdateCleanup.ps1').read_text(encoding='utf-8-sig')
        cls.build=(ROOT/'builder/build_windows.ps1').read_text(encoding='utf-8-sig')
        cls.hash=(ROOT/'builder/InstallHash.cs').read_text()
    def test_required_sources_exist(self):
        for x in ['ZenBrowserPortable.cs','InstallHash.cs','hash_test.cs','ZenUpdateCleanup.ps1','build_windows.ps1','verify_zip.py']:
            self.assertTrue((ROOT/'builder'/x).is_file(),x)
    def test_no_manual_approval_parameter_or_mode(self):
        self.assertNotIn("Read-Host",self.clean)
        self.assertNotIn("'Configure'",self.clean)
        self.assertIn('-InstallHash',self.launch)
        self.assertIn("ValidatePattern('^[0-9A-Fa-f]{16}$')",self.clean)
    def test_launcher_subprocess_only_redirection(self):
        for name in ['TEMP','TMP','APPDATA','LOCALAPPDATA']:
            self.assertIn('psi.EnvironmentVariables["'+name+'"]',self.launch)
        self.assertNotIn('Environment.SetEnvironmentVariable',self.launch)
    def test_safe_profile_startup(self):
        self.assertIn('Data\\Profile',self.launch)
        self.assertIn('--no-remote --profile',self.launch)
        self.assertIn('WaitForZenShutdown(root)',self.launch)
        self.assertIn('TryPostExitCleanup(root, installHash)',self.launch)
        self.assertNotIn('Process.Kill()',self.launch)
    def test_install_hash_from_actual_current_binary(self):
        self.assertIn('InstallHash.ForDirectory(Path.GetDirectoryName(exe))',self.launch)
        self.assertIn('CityHash64(Encoding.Unicode.GetBytes(dir))',self.hash)
        self.assertIn('SOFTWARE\\Mozilla\\Zen\\TaskBarIDs',self.hash)
        self.assertIn('OrdinalIgnoreCase',self.hash)
        self.assertIn('CityHash64 vectors: PASS', (ROOT/'builder/hash_test.cs').read_text())
    def test_hash_selftest_runs_before_winexe_compile(self):
        self.assertLess(self.build.index('& $hashTest'),self.build.index('/target:winexe'))
        self.assertIn('builder\\InstallHash.cs',self.build)
    def test_no_shared_programdata_recursive_delete(self):
        self.assertNotIn('Remove-Item -Recurse',self.clean)
        self.assertIn('Test-NoLinkedAncestors',self.clean)
        self.assertIn('Clean-Approved $folder',self.clean)
        self.assertIn('$InstallHash.ToUpperInvariant()',self.clean)
        self.assertIn('Mozilla-1de4eec8-1241-4177-a864-e594e8d1fb38',self.clean)
        self.assertIn("$allowFiles = @('update-config.json','parent.lock')",self.clean)
        self.assertIn('Backups',self.clean)
    def test_shortcuts_verify_targets(self):
        self.assertIn('Test-PortableShortcut',self.clean)
        self.assertIn('private_browsing.exe',self.clean)
        self.assertIn('shortcut belongs to a different target',self.clean)
    def test_policy_and_program_binary_pinned(self):
        for x in ['DisableAppUpdate','DisableDefaultBrowserAgent','DontCheckDefaultBrowser']:
            self.assertIn(x,self.build)
        self.assertIn('Get-FileHash',self.build)
        self.assertIn('asset.digest',self.build)
        self.assertIn('App\\Zen\\zen.exe',self.launch)
    def test_data_not_deleted_by_build(self):
        self.assertNotIn('Remove-Item $package -Recurse',self.build)
        self.assertIn('Data\\HostEnvironment',self.build)
        self.assertIn('Data\\Profile',self.build)
    def test_clean_zip_check_requires_no_profile(self):
        spec=importlib.util.spec_from_file_location('verify_zip',ROOT/'builder/verify_zip.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        names=['ZenBrowserPortable.exe','App/Zen/zen.exe','App/Zen/omni.ja','App/Zen/xul.dll','App/Zen/distribution/policies.json','App/AppInfo/appinfo.ini','App/AppInfo/appicon.ico','Other/README.txt','Other/ZenUpdateCleanup.ps1','App/Zen/browser/chrome.manifest']+[f'App/AppInfo/appicon_{x}.png' for x in [16,32,75,128,256]]
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'x.zip'
            with zipfile.ZipFile(path,'w') as z:
                for x in names:z.writestr('ZenBrowserPortable/'+x,'x')
            self.assertTrue(mod.verify(path))
            with zipfile.ZipFile(path,'a') as z:z.writestr('ZenBrowserPortable/Data/Profile/logins.json','private')
            with self.assertRaisesRegex(RuntimeError,'profile'):mod.verify(path)
if __name__=='__main__':unittest.main()
