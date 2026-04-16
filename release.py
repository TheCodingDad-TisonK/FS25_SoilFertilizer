import zipfile, os

MOD_DIR = os.getcwd()
MOD_NAME = os.path.basename(MOD_DIR)
ZIP_PATH = os.path.join(os.path.dirname(MOD_DIR), MOD_NAME + ".zip")

EXCLUDE_DIRS  = {".git", ".claude", "__MACOSX", ".github"}
EXCLUDE_EXTS  = {".sh", ".py", ".md", ".DS_Store", ".zip", ".png", ".txt", ".yml"}
EXCLUDE_FILES = {".gitignore", "LICENSE", "CLAUDE.md", "CONTRIBUTING.md", "DEVELOPMENT.md", "README.md", "CHANGELOG.md", "icon_source.png", "config.txt"}

with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(MOD_DIR):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for fname in files:
            if fname in EXCLUDE_FILES: continue
            if any(fname.endswith(ext) for ext in EXCLUDE_EXTS): continue
            full_path = os.path.join(root, fname)
            arc_name = os.path.relpath(full_path, MOD_DIR).replace("\\", "/")
            zf.write(full_path, arc_name)

print(f"Created {ZIP_PATH}")