import os
import zipfile
import shutil
import sys
import argparse

MOD_NAME = "FS25_SoilFertilizer"
MOD_DIR = os.path.dirname(os.path.abspath(__file__))
PARENT_DIR = os.path.dirname(MOD_DIR)
ZIP_NAME = f"{MOD_NAME}.zip"
ZIP_PATH = os.path.join(PARENT_DIR, ZIP_NAME)

# Resolve default mods directory
USER_PROFILE = os.environ.get("USERPROFILE", os.path.expanduser("~"))
DEFAULT_MODS_DIR = os.path.join(USER_PROFILE, "Documents", "My Games", "FarmingSimulator2025", "mods")

EXCLUDE_DIRS = {".git", ".claude", "__MACOSX", ".github"}
EXCLUDE_EXTS = {".sh", ".py", ".md", ".DS_Store", ".zip", ".png", ".txt", ".gitignore", ".LICENSE"}
EXCLUDE_FILES = {".gitignore", "LICENSE", "config.txt", "icon_source.png", "build.sh"}

def build():
    print("============================================")
    print(f"  Building {MOD_NAME}")
    print("============================================")

    if os.path.exists(ZIP_PATH):
        os.remove(ZIP_PATH)
        print("  Removed old zip")

    with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(MOD_DIR):
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
            for fname in files:
                if fname in EXCLUDE_FILES:
                    continue
                if any(fname.endswith(ext) for ext in EXCLUDE_EXTS):
                    continue
                full_path = os.path.join(root, fname)
                arc_name = os.path.relpath(full_path, MOD_DIR).replace("\\", "/")
                zf.write(full_path, arc_name)
                print(f"  + {arc_name}")

    print(f"\n  ZIP created: {ZIP_PATH}")
    return ZIP_PATH

def deploy(zip_path, mods_dir=None):
    if mods_dir is None:
        mods_dir = DEFAULT_MODS_DIR
    print(f"\n  Deploying to: {mods_dir}")
    if not os.path.isdir(mods_dir):
        print(f"  ERROR: Mods folder not found at: {mods_dir}")
        sys.exit(1)
    dest_path = os.path.join(mods_dir, ZIP_NAME)
    if os.path.exists(dest_path):
        os.remove(dest_path)
    shutil.copy2(zip_path, dest_path)
    print(f"  Deployed: {dest_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build and deploy FS25 mod")
    parser.add_argument("--deploy", action="store_true", help="Deploy to mods folder after building")
    parser.add_argument("--mods-dir", type=str, help="Custom mods directory path")
    args = parser.parse_args()
    zip_out = build()
    if args.deploy:
        deploy(zip_out, args.mods_dir)
    print("\n  Done. Check log.txt for [SoilFert] entries after launching.")
    print("============================================")
