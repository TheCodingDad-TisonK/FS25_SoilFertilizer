#!/usr/bin/env python3
"""
Build script for FS25_SoilFertilizer mod
Creates a clean zip file with only necessary mod files
"""

import zipfile
import os
from pathlib import Path

# Files and directories to include in the mod zip
INCLUDE_PATTERNS = [
    'icon.dds',
    'modDesc.xml',
    'src/**/*.lua',
]

# Files and directories to exclude
EXCLUDE_PATTERNS = [
    '*.git*',
    '*.md',
    '*.txt',
    '*.py',
    '__pycache__',
    '*.pyc',
    '.vscode',
    '.idea',
    'build',
    'dist',
]

def should_include(path):
    """Check if a file should be included in the zip"""
    path_str = str(path)

    # Check exclusions first
    for pattern in EXCLUDE_PATTERNS:
        if pattern.startswith('*'):
            if path_str.endswith(pattern[1:]):
                return False
        elif pattern in path_str:
            return False

    return True

def build_mod():
    """Build the mod zip file"""
    script_dir = Path(__file__).parent
    mod_name = 'FS25_SoilFertilizer'
    output_file = script_dir / f'{mod_name}.zip'

    print(f"Building {mod_name}...")
    print(f"Output: {output_file}")

    # Remove old zip if it exists
    if output_file.exists():
        output_file.unlink()
        print(f"Removed old {output_file.name}")

    # Create new zip
    with zipfile.ZipFile(output_file, 'w', zipfile.ZIP_DEFLATED) as zipf:
        # Add icon
        icon_path = script_dir / 'icon.dds'
        if icon_path.exists():
            zipf.write(icon_path, 'icon.dds')
            print(f"  + icon.dds")

        # Add modDesc.xml
        moddesc_path = script_dir / 'modDesc.xml'
        if moddesc_path.exists():
            zipf.write(moddesc_path, 'modDesc.xml')
            print(f"  + modDesc.xml")

        # Add all .lua files from src/
        src_dir = script_dir / 'src'
        if src_dir.exists():
            for lua_file in src_dir.rglob('*.lua'):
                if should_include(lua_file):
                    rel_path = lua_file.relative_to(script_dir)
                    zipf.write(lua_file, str(rel_path))
                    print(f"  + {rel_path}")

    # Get file size
    size_kb = output_file.stat().st_size / 1024
    print(f"\n✓ Build complete: {output_file.name} ({size_kb:.1f} KB)")

    return output_file

if __name__ == '__main__':
    try:
        output = build_mod()
        print("\n✓ Mod built successfully!")
    except Exception as e:
        print(f"\n✗ Build failed: {e}")
        exit(1)
