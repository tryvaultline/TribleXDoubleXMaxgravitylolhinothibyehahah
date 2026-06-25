import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const scanRoots = ["Maxgravity", "Maxgravity.xcodeproj"];
const privatePatterns = [
  "_UILiquidLensView",
  "NSClassFromString",
  "CABackdropLayer"
];
const hits = [];

async function walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(full);
      continue;
    }
    if (!/\.(swift|pbxproj|plist)$/i.test(entry.name)) {
      continue;
    }
    const text = await readFile(full, "utf8");
    for (const pattern of privatePatterns) {
      if (text.includes(pattern)) {
        hits.push(`${path.relative(root, full)} :: ${pattern}`);
      }
    }
  }
}

for (const scanRoot of scanRoots) {
  await walk(path.join(root, scanRoot));
}

if (hits.length > 0) {
  console.error("Private Apple API references are not allowed in the shipping app:");
  for (const hit of hits) {
    console.error(`- ${hit}`);
  }
  process.exit(1);
}

console.log("No private Apple API references found in the iOS target.");
