"""Resolve verified upstream Zen release and a safe, version-matched release tag.

Run from GitHub Actions. Uses only the Python standard library; refuses to make
claims about Windows runtime portability.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

UPSTREAM = 'zen-browser/desktop'
API = 'https://api.github.com'
VERSION = re.compile(r'^\d+\.\d+(?:\.\d+)?b$')
REVISION = re.compile(r'^r[1-9]\d*$')
SHA = re.compile(r'^sha256:([a-fA-F0-9]{64})$')


def github_json(path: str, token: str = '', *, allow_404: bool = False):
    url = f'{API}{path}'
    headers = {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'ZenBrowser-Portable-AutoLatest',
        'X-GitHub-Api-Version': '2022-11-28',
    }
    if token:
        headers['Authorization'] = f'Bearer {token}'
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if allow_404 and exc.code == 404:
            return None
        raise RuntimeError(f'GitHub API request failed ({exc.code}): {path}') from exc


def safe_version(version: str) -> str:
    if not VERSION.fullmatch(version):
        raise ValueError(f'Not an official Zen stable tag format: {version!r}')
    return version


def numeric_version(version: str) -> str:
    match = re.fullmatch(r'(\d+)\.(\d+)(?:\.(\d+))?b', safe_version(version))
    assert match
    return f'{int(match[1])}.{int(match[2])}.{int(match[3] or 0)}.0'


def validate_release(release: dict, wanted: str, arch: str) -> tuple[str, str]:
    if release.get('draft') or release.get('prerelease'):
        raise ValueError('Upstream release is a draft/prerelease; stable packages only')
    version = safe_version(str(release.get('tag_name', '')))
    if wanted and version != wanted:
        raise ValueError(f'Upstream tag mismatch: requested {wanted}, got {version}')
    asset_name = 'zen.installer.exe' if arch == 'x64' else 'zen.installer-arm64.exe'
    assets = [a for a in release.get('assets', []) if a.get('name') == asset_name]
    if len(assets) != 1:
        raise ValueError(f'Expected exactly one upstream {asset_name}, found {len(assets)}')
    asset = assets[0]
    digest_match = SHA.fullmatch(str(asset.get('digest') or ''))
    if not digest_match:
        raise ValueError('Official asset SHA-256 digest missing or invalid: fail closed')
    if int(asset.get('size') or 0) < 50_000_000:
        raise ValueError(f'Upstream asset suspiciously small: {asset_name}')
    expected_url = f'https://github.com/{UPSTREAM}/releases/download/{version}/{asset_name}'
    if asset.get('browser_download_url') != expected_url:
        raise ValueError('Upstream asset URL does not point to the expected official repo')
    return version, digest_match[1].lower()


def tag_for(version: str, architecture: str, revision: str) -> str:
    safe_version(version)
    if architecture not in ('x64', 'arm64'):
        raise ValueError(f'Unsupported architecture: {architecture}')
    if not REVISION.fullmatch(revision):
        raise ValueError(f'Invalid revision {revision!r}: use r1, r2, ...')
    return f'portable-v{version}-zen-{architecture}-nsis-{revision}'


def check_existing(release: dict, version: str, architecture: str, revision: str) -> bool:
    """Return True only for an apparently complete, correctly labeled release.

    Names and metadata are not binary proof; old releases must still be tested.
    Incomplete/mislabeled releases fail instead of being silently skipped.
    """
    if release.get('draft'):
        raise ValueError('Existing release is a draft; do not overwrite it')
    if version not in str(release.get('name') or ''):
        raise ValueError('Existing release title/version mismatch; choose a new revision')
    names = {a.get('name', '') for a in release.get('assets') or []}
    expected_zip = f'ZenBrowser-{version}-{architecture}-Portable.zip'
    zip_ok = expected_zip in names
    paf_ok = any(name.lower().endswith('.paf.exe') and
                 numeric_version(version) in name and revision in name
                 for name in names)
    checksums = 'SHA256SUMS.txt' in names
    if not (zip_ok and paf_ok and checksums):
        raise ValueError('Existing tag is incomplete or mislabeled; do not reuse it. Increment package_revision.')
    return True


def write_outputs(outputs: dict):
    target = os.environ.get('GITHUB_OUTPUT')
    if target:
        with open(target, 'a', encoding='utf-8') as file:
            for key, value in outputs.items():
                file.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
    for key, value in outputs.items():
        print(f'{key}: {value}')
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as file:
            file.write('## Zen Browser Auto-Latest discovery\n\n')
            for key, value in outputs.items():
                if key != 'sha256':
                    file.write(f'- **{key}**: `{value}`\n')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', default='', help='Empty = latest stable')
    parser.add_argument('--architecture', choices=('x64', 'arm64'), default='x64')
    parser.add_argument('--revision', default='r1')
    parser.add_argument('--publish', choices=('true', 'false'), default='true')
    parser.add_argument('--rebuild-existing', choices=('true', 'false'), default='false')
    args = parser.parse_args()
    version_override = args.version.strip()
    if version_override:
        safe_version(version_override)
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN', '')
    if version_override:
        path = f'/repos/{UPSTREAM}/releases/tags/{urllib.parse.quote(version_override, safe="")}'
    else:
        path = f'/repos/{UPSTREAM}/releases/latest'
    release = github_json(path, token)
    version, expected_sha = validate_release(release, version_override, args.architecture)
    tag = tag_for(version, args.architecture, args.revision)
    repo = os.environ.get('GITHUB_REPOSITORY', 'vhick/ZenBrowser-Portable-Builder')
    existing = github_json(f'/repos/{repo}/releases/tags/{urllib.parse.quote(tag, safe="")}', token, allow_404=True)
    if existing:
        if args.rebuild_existing == 'true':
            if args.publish == 'true':
                raise ValueError('Cannot rebuild existing tag and publish. Set publish=false or increment revision.')
            build = True
            reason = 'explicit local test rebuild of existing version; publishing disabled'
        else:
            check_existing(existing, version, args.architecture, args.revision)
            build = False
            reason = 'complete matching release already exists'
    else:
        # A preexisting git tag without a Release is a collision, not a free tag.
        tag_ref = github_json(f'/repos/{repo}/git/ref/tags/{urllib.parse.quote(tag, safe="")}', token, allow_404=True)
        if tag_ref is not None:
            raise ValueError(f'Git tag already exists without a Release: {tag}. Change revision.')
        build = True
        reason = 'no existing published tag'
    write_outputs({'version': version, 'numeric_version': numeric_version(version),
                   'architecture': args.architecture, 'revision': args.revision,
                   'tag': tag, 'sha256': expected_sha, 'build': build, 'reason': reason})
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, RuntimeError, urllib.error.URLError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
