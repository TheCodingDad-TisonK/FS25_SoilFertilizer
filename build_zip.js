const fs = require('fs');
const path = require('path');
const archiver = require('archiver');

const MOD_NAME = "FS25_SoilFertilizer";
const ZIP_PATH = path.join(__dirname, '..', `${MOD_NAME}.zip`);

const EXCLUDE_DIRS = new Set([".git", ".claude", "__MACOSX"]);
const EXCLUDE_EXTS = new Set([".sh", ".py", ".md", ".DS_Store", ".zip", ".png", ".txt", ".js"]);
const EXCLUDE_FILES = new Set([".gitignore", "patch.js", "patch_icons.js", "build.sh", "build.py", "build.zip", "LICENSE", "CONTRIBUTING.md", "DEVELOPMENT.md", "README.md", "CHANGELOG.md", "CLAUDE.md", "icon_badge_final.png", "config.txt", "icon_source.png"]);

function zipDirectory(source, out) {
  const archive = archiver('zip', { zlib: { level: 9 } });
  const stream = fs.createWriteStream(out);

  return new Promise((resolve, reject) => {
    archive
      .directory(source, false, (data) => {
        const name = data.name;
        const ext = path.extname(name);
        const parts = name.split(/[/\\]/);
        
        if (EXCLUDE_DIRS.has(parts[0])) return false;
        if (EXCLUDE_FILES.has(name)) return false;
        if (EXCLUDE_EXTS.has(ext)) return false;
        
        return data;
      })
      .on('error', err => reject(err))
      .pipe(stream);

    stream.on('close', () => resolve());
    archive.finalize();
  });
}

zipDirectory(__dirname, ZIP_PATH)
  .then(() => console.log(`ZIP created successfully at ${ZIP_PATH}`))
  .catch(err => console.error('Error creating zip:', err));
