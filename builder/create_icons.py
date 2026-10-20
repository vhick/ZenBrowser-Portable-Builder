"""Extract the original, complete multi-resolution icon from official Zen's zen.exe."""
from pathlib import Path
import argparse
from icoextract import IconExtractor
from PIL import Image


def extract_icons(exe: Path, appinfo: Path):
    if not exe.is_file():
        raise FileNotFoundError(f"Official Zen executable missing: {exe}")
    appinfo.mkdir(parents=True, exist_ok=True)
    ico = appinfo / 'appicon.ico'
    # Export actual icon group from the Zen Browser binary, rather than a generic
    # Windows ExtractAssociatedIcon bitmap (which can lose resolutions).
    IconExtractor(str(exe)).export_icon(str(ico), num=0)
    with Image.open(ico) as im:
        for size in (16, 32, 75, 128, 256):
            # Use the highest-quality icon inside the multi-resolution .ico.
            candidate_sizes = sorted(im.ico.sizes(), key=lambda pair: pair[0] * pair[1])
            candidates = [s for s in candidate_sizes if min(s) >= size]
            target = candidates[0] if candidates else candidate_sizes[-1]
            src = im.ico.getimage(target).convert('RGBA')
            if src.size != (size, size):
                src = src.resize((size, size), Image.Resampling.LANCZOS)
            src.save(appinfo / f'appicon_{size}.png')
    return ico


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('exe', type=Path)
    parser.add_argument('appinfo_dir', type=Path)
    args = parser.parse_args()
    print(extract_icons(args.exe, args.appinfo_dir))
