#!/usr/bin/env python3
"""Build the btrfs-cow Plymouth theme into build/.

  build/btrfs-cow/          what `make install` copies to /usr/share/plymouth/themes.
                            The script keeps @HOST@/@KERNEL@/@SUBVOL@ placeholders;
                            the btrfs-cow-theme mkinitcpio hook fills them per kernel.
  build/preview/btrfs-cow-preview/
                            same theme with this machine's values filled in now,
                            for scripts/preview.sh.
"""
import base64
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
THEMES = Path("/usr/share/plymouth/themes")
ACCENT = os.environ.get("ACCENT", "#5ef2b8")
CHROME = next((c for c in ("google-chrome-stable", "google-chrome", "chromium") if shutil.which(c)), None)


def render_assets():
    if not CHROME:
        sys.exit("need google-chrome or chromium to render the theme images")
    url = (ROOT / "tools/gen-assets.html").as_uri() + "?accent=" + ACCENT.replace("#", "%23")
    with tempfile.TemporaryDirectory() as profile:
        dom = subprocess.run(
            [CHROME, "--headless=new", "--disable-gpu", f"--user-data-dir={profile}",
             "--virtual-time-budget=2000", "--dump-dom", url],
            check=True, capture_output=True, text=True, timeout=120,
        ).stdout
    m = re.search(r'<pre id="out">(.*?)</pre>', dom, re.S)
    if not m or not m.group(1).strip():
        sys.exit("asset generator produced no output")
    return {name: base64.b64decode(url.split(",", 1)[1])
            for name, url in json.loads(html.unescape(m.group(1))).items()}


def write_theme(dest, name, assets, values=None):
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for fname, data in assets.items():
        (dest / fname).write_bytes(data)
    script = (ROOT / "theme/btrfs-cow.script").read_text()
    for key, val in (values or {}).items():
        script = script.replace(f"@{key}@", val)
    (dest / f"{name}.script").write_text(script)
    plymouth = (ROOT / "theme/btrfs-cow.plymouth").read_text()
    plymouth = plymouth.replace("@NAME@", name).replace("@DIR@", str(THEMES / name))
    (dest / f"{name}.plymouth").write_text(plymouth)


def machine_values():
    host = Path("/etc/hostname").read_text().strip() if Path("/etc/hostname").exists() else os.uname().nodename
    m = re.search(r"rootflags=\S*?subvol=([^\s,]+)", Path("/proc/cmdline").read_text())
    return {"HOST": host, "KERNEL": os.uname().release, "SUBVOL": m.group(1) if m else "/"}


def main():
    assets = render_assets()
    write_theme(BUILD / "btrfs-cow", "btrfs-cow", assets)
    write_theme(BUILD / "preview/btrfs-cow-preview", "btrfs-cow-preview", assets, machine_values())
    print(f"built {len(assets)} images -> {BUILD.relative_to(ROOT)}/btrfs-cow (accent {ACCENT})")


if __name__ == "__main__":
    main()
