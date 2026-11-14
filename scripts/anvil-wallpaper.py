#!/usr/bin/env python3
"""Choose one local wallpaper per Anvil session; swaybg owns its lifetime."""
import os
from pathlib import Path
import random
import sys

root = Path.home() / ".wallpapers" / "files"
images = sorted(path for path in root.rglob("*")
                if path.is_file() and path.stat().st_size > 0 and path.suffix.lower() in {".png", ".jpg", ".jpeg"})
if not images:
    print(f"anvil-wallpaper: no images in {root}", file=sys.stderr)
    sys.exit(0)
wallpaper = random.choice(images)
print(f"anvil-wallpaper: {wallpaper}", file=sys.stderr, flush=True)
os.execvp("swaybg", ["swaybg", "--image", str(wallpaper), "--mode", "fill"])
