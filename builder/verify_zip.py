"""Fail closed if the PortableApps ZIP structure is incomplete or leaks user data."""
import sys
from pathlib import Path
from zipfile import ZipFile


def verify(zip_path: Path):
    with ZipFile(zip_path) as z:
        names = set(z.namelist())
        prefix = 'ZenBrowserPortable/'
        expected = [
            'ZenBrowserPortable.exe',
            'App/Zen/zen.exe',
            'App/Zen/omni.ja',
            'App/Zen/xul.dll',
            'App/Zen/distribution/policies.json',
            'App/AppInfo/appinfo.ini',
            'App/AppInfo/appicon.ico',
            'Other/README.txt',
            'Other/ZenUpdateCleanup.ps1',
        ] + [f'App/AppInfo/appicon_{n}.png' for n in (16,32,75,128,256)]
        missing = [p for p in expected if prefix + p not in names]
        if missing:
            raise RuntimeError('Missing package members: ' + ', '.join(missing))
        unwanted = [n for n in names if n.startswith(prefix + 'Data/Profile/') and
                    not n.endswith('/') and not n.endswith('README.txt')]
        if unwanted:
            raise RuntimeError('Build artifact contains a browser profile or user data!')
        if prefix + 'Data/UpdaterCleanup/approved-update-folder.txt' in names:
            raise RuntimeError('Builder must not ship machine-specific cleanup approval!')
        if not any(n.startswith(prefix + 'App/Zen/browser/') for n in names):
            raise RuntimeError('Zen browser assets missing from archive')
    return True


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
    print('Zen Browser portable ZIP: structure and clean Data checks passed')
