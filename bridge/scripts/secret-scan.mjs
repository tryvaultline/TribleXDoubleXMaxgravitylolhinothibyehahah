import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..", "..");
const ignoredDirs = new Set([".git", "node_modules", "dist", "outputs"]);
const patterns = [
  /gh[pousr]_[A-Za-z0-9_]{36,}/,
  /xox[baprs]-[A-Za-z0-9-]{20,}/,
  /AKIA[0-9A-Z]{16}/,
  /-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----/,
  /APPLE_[A-Z_]*SECRET\s*=\s*['"][^'"]+['"]/i
];

const hits = [];

async function walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (ignoredDirs.has(entry.name)) {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(full);
      continue;
    }
    if (!/\.(ts|js|json|md|yml|yaml|plist|pbxproj)$/i.test(entry.name)) {
      continue;
    }
    const text = await readFile(full, "utf8");
    for (const pattern of patterns) {
      if (pattern.test(text)) {
        hits.push(path.relative(root, full));
      }
    }
  }
}

await walk(root);

if (hits.length > 0) {
  console.error("Potential committed secret material found:");
  for (const hit of hits) {
    console.error(`- ${hit}`);
  }
  process.exit(1);
}

console.log("No obvious secret material detected.");
