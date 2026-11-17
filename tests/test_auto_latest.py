"""Portable release workflow logic: fully offline, uses the Python stdlib only."""
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'builder'))
from zen_release_resolver import (
    safe_version, numeric_version, validate_release, tag_for, check_existing
)
from verify_auto_package import audit


SHA = 'a' * 64


def release(version='1.24.2b', arch='x64'):
    name = 'zen.installer.exe' if arch == 'x64' else 'zen.installer-arm64.exe'
    return {'tag_name': version, 'draft': False, 'prerelease': False,
            'assets': [{'name': name, 'size': 120_000_000,
                        'digest': f'sha256:{SHA}',
                        'browser_download_url': f'https://github.com/zen-browser/desktop/releases/download/{version}/{name}'}]}


class TestZenReleaseResolver(unittest.TestCase):
    def test_stable_tags(self):
        for tag in ('1.24b', '1.24.2b', '2.0.10b'):
            self.assertEqual(safe_version(tag), tag)
        for tag in ('1.24.2a', 'nightly', 'v1.24.2b', '1.24.2b\nfoo', '1.2.3'):
            with self.assertRaises(ValueError): safe_version(tag)

    def test_numeric_version(self):
        self.assertEqual(numeric_version('1.24b'), '1.24.0.0')
        self.assertEqual(numeric_version('1.24.2b'), '1.24.2.0')

    def test_release_assets(self):
        for arch in ('x64', 'arm64'):
            self.assertEqual(validate_release(release(arch=arch), '', arch), ('1.24.2b', SHA))
        bad = release()
        bad['assets'][0]['digest'] = ''
        with self.assertRaisesRegex(ValueError, 'SHA-256'): validate_release(bad, '', 'x64')

    def test_reject_mismatched_version_and_unofficial_url(self):
        with self.assertRaisesRegex(ValueError, 'tag mismatch'):
            validate_release(release(), '1.24.1b', 'x64')
        r = release()
        r['assets'][0]['browser_download_url'] = 'https://example.com/zen.installer.exe'
        with self.assertRaisesRegex(ValueError, 'URL'):
            validate_release(r, '', 'x64')

    def test_reject_draft(self):
        r = release(); r['draft'] = True
        with self.assertRaisesRegex(ValueError, 'draft'):
            validate_release(r, '', 'x64')

    def test_tag_format_and_revision(self):
        self.assertEqual(tag_for('1.24.2b', 'x64', 'r2'),
                         'portable-v1.24.2b-zen-x64-nsis-r2')
        with self.assertRaises(ValueError): tag_for('1.24.2b', 'x64', 'latest')

    def test_existing_full_and_partial_releases(self):
        good = {'name': 'Zen Browser Portable 1.24.2b (x64, r1)', 'draft': False,
                'assets': [{'name': n} for n in (
                    'ZenBrowser-1.24.2b-x64-Portable.zip',
                    'ZenBrowserPortableCommunity_1.24.2.0_custom-nsis-r1.paf.exe',
                    'SHA256SUMS.txt')]}
        self.assertTrue(check_existing(good, '1.24.2b', 'x64', 'r1'))
        good['assets'] = good['assets'][:1]
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            check_existing(good, '1.24.2b', 'x64', 'r1')

    def test_bad_zip_stops_publish(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            name = 'ZenBrowser-1.24.2b-x64-Portable.zip'
            with ZipFile(root / name, 'w') as z:
                z.writestr('ZenBrowserPortable/App/AppInfo/appinfo.ini',
                           '[Version]\nDisplayVersion=1.23.4b\n')
            with self.assertRaises(RuntimeError):
                audit(root, root / name, '1.24.2b', 'x64', SHA, root, 'r1')


if __name__ == '__main__':
    unittest.main()
