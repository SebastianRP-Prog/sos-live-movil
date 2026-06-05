const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..", "..", "frontend", "lib");

const replacements = [
  ["\u00c3\u00a1", "á"],
  ["\u00c3\u00a9", "é"],
  ["\u00c3\u00ad", "í"],
  ["\u00c3\u00b3", "ó"],
  ["\u00c3\u00ba", "ú"],
  ["\u00c3\u00b1", "ñ"],
  ["\u00c3\u0081", "Á"],
  ["\u00c3\u0089", "É"],
  ["\u00c3\u008d", "Í"],
  ["\u00c3\u0093", "Ó"],
  ["\u00c3\u009a", "Ú"],
  ["\u00c3\u0091", "Ñ"],
  ["\u00c3\u00bc", "ü"],
  ["\u00c2\u00bf", "¿"],
  ["\u00c2\u00a1", "¡"],
  ["\u00e2\u20ac\u201d", "-"],
  ["\u00e2\u20ac\u201c", "-"],
  ["\u00e2\u20ac\u0153", "\""],
  ["\u00e2\u20ac\u009d", "\""],
  ["\u00e2\u20ac\u02dc", "'"],
  ["\u00e2\u20ac\u2122", "'"],
  ["\u00e2\u0153\u2026", "OK"],
  ["\u00e2\u0161\u00a0\u00ef\u00b8\u008f", "Alerta"],
  ["\u00e2\u008f\u00b1\u00ef\u00b8\u008f", "Tiempo"],
  ["\u00f0\u0178\u0161\u00a8", "SOS"],
  ["\u00f0\u0178\u201c\u00a7", "Correo"],
  ["\u00e2\u201d\u20ac", "-"],
];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath);
    } else if (entry.isFile() && entry.name.endsWith(".dart")) {
      let content = fs.readFileSync(fullPath, "utf8");
      const original = content;
      for (const [bad, good] of replacements) {
        content = content.split(bad).join(good);
      }
      if (content !== original) {
        fs.writeFileSync(fullPath, content, "utf8");
        console.log(`fixed ${path.relative(root, fullPath)}`);
      }
    }
  }
}

walk(root);
