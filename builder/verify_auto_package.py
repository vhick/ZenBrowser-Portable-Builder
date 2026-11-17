"""Validate staged Zen portable ZIP and independent installer before publication."""
from __future__ import annotations
import argparse
import configparser
import hashlib
from pathlib import Path
from zipfile import ZipFile

from zen_release_resolver import numeric_version, safe_version


def ensure_pe(path: Path):
    if not path.is_file() or path.stat().st_size < 2:
        raise RuntimeError(f'Missing or empty executable: {path}')
    with path.open('rb') as stream:
        if stream.read(2) != b'MZ':
            raise RuntimeError(f'Not a Windows executable: {path}')


def audit(root: Path, archive: Path, version: str, architecture: str, sha256: str,
          outdir: Path, revision: str):
    safe_version(version)
    if architecture not in ('x64', 'arm64'):
        raise RuntimeError('Invalid architecture')
    expected_zip = f'ZenBrowser-{version}-{architecture}-Portable.zip'
    if archive.name != expected_zip or not archive.is_file():
        raise RuntimeError(f'ZIP name must be {expected_zip}')
    if len(sha256) != 64 or any(c not in '0123456789abcdef' for c in sha256.lower()):
        raise RuntimeError('Missing official SHA-256')
    cfg_path = root / 'App' / 'AppInfo' / 'appinfo.ini'
    if not cfg_path.is_file():
        raise RuntimeError('Missing AppInfo')
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str
    cfg.read(cfg_path, encoding='utf-8-sig')
    if cfg.get('Version', 'DisplayVersion') != version:
        raise RuntimeError('AppInfo display version mismatch')
    if cfg.get('Version', 'PackageVersion') != numeric_version(version):
        raise RuntimeError('AppInfo package version mismatch')
    if cfg.get('Details', 'AppID') != 'ZenBrowserPortableCommunity':
        raise RuntimeError('Unexpected portable AppID')
    if cfg.get('Control', 'Start') != 'ZenBrowserPortable.exe':
        raise RuntimeError('Incorrect root launcher')
    ensure_pe(root / 'ZenBrowserPortable.exe')
    ensure_pe(root / 'App' / 'Zen' / 'zen.exe')
    for name in ('omni.ja', 'xul.dll', 'distribution/policies.json'):
        if not (root / 'App' / 'Zen' / name).is_file():
            raise RuntimeError(f'Incomplete Zen installation: {name}')
    readme = (root / 'Other' / 'README.txt').read_text(encoding='utf-8-sig')
    if f'preview {version} ({architecture})' not in readme:
        raise RuntimeError('Application version does not match packaged readme')
    if sha256.lower() not in readme.lower():
        raise RuntimeError('Official installer hash not recorded in package')
    profile = root / 'Data' / 'Profile'
    if profile.is_dir() and any(p.is_file() for p in profile.rglob('*')):
        raise RuntimeError('Refusing to publish a user profile')
    # Checks both ZIP naming and content; original builder also runs verify_zip.py.
    with ZipFile(archive) as z:
        if z.testzip() is not None:
            raise RuntimeError('ZIP CRC error')
        prefix = 'ZenBrowserPortable/'
        entries = set(z.namelist())
        if prefix + 'App/AppInfo/appinfo.ini' not in entries:
            raise RuntimeError('ZIP AppInfo missing')
        zip_ini = configparser.ConfigParser(interpolation=None)
        zip_ini.optionxform = str
        zip_ini.read_string(z.read(prefix + 'App/AppInfo/appinfo.ini').decode('utf-8-sig'))
        if zip_ini.get('Version', 'DisplayVersion') != version:
            raise RuntimeError('ZIP embeds a different browser version')
        if any(x.startswith(prefix + 'Data/Profile/') and not x.endswith('/') for x in entries):
            raise RuntimeError('ZIP contains profile files')
    installers = list(outdir.glob('*.paf.exe'))
    if len(installers) != 1:
        raise RuntimeError(f'Expected one PAF installer, found {len(installers)}')
    installer = installers[0]
    if numeric_version(version) not in installer.name or revision not in installer.name:
        raise RuntimeError(f'PAF installer name/revision does not match {version} {revision}')
    ensure_pe(installer)
    if installer.stat().st_size < 100_000:
        raise RuntimeError('PAF is unexpectedly small')
    for artifact in (archive, installer):
        print(f'VALIDATED {artifact.name} SHA256={hashlib.sha256(artifact.read_bytes()).hexdigest()}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--zip', type=Path, required=True)
    parser.add_argument('--outdir', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--architecture', required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--revision', required=True)
    args = parser.parse_args()
    audit(args.root, args.zip, args.version, args.architecture,
          args.sha256, args.outdir, args.revision)
    print('Zen ZIP and independent NSIS package metadata match release tag.')


if __name__ == '__main__':
    main()
