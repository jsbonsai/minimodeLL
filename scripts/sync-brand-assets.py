#!/usr/bin/env python3
"""Copy the macOS runtime subset from the supplied design kit; preserve original artwork."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
source = root / 'design-assets/minimodeLL-brand'
destination = root / 'Sources/MinimodeLL/Resources/BrandAssets'
destination.mkdir(parents=True, exist_ok=True)
files = {f'menubar/png/{name}{scale}.png': f'{name}{scale}.png'
         for name in ['MenuBarIconTemplate', 'MenuBarIconIdleTemplate', 'MenuBarIconOffTemplate']
         for scale in ['', '@2x', '@3x']}
for name in ['Geist-Regular.otf', 'Geist-Bold.otf', 'Geist-SemiBold.otf', 'GeistMono-Regular.otf', 'OFL.txt']:
    files[f'fonts/{name}'] = name
files.update({'app-icon/AppIcon.icns': 'AppIcon.icns', 'tokens/tokens.json': 'tokens.json'})
for name in ['BrandInk', 'BrandMuted', 'BrandSurface', 'AccentColor']:
    files[f'xcode/Assets.xcassets/{name}.colorset/Contents.json'] = f'{name}.json'
for original, installed in files.items():
    shutil.copyfile(source / original, destination / installed)
print(f'Synchronized {len(files)} brand resources.')
