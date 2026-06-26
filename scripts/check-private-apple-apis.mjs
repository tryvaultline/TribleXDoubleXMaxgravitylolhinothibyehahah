import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const scanDirs = ["Maxgravity", "Maxgravity.xcodeproj"];
const forbidden = [
  "_UILiquidLensView",
  "NSClassFromString",
  "CABackdropLayer",
  "UIWebView",
  "LiquidGlassPrivate",
  "privateAppleGlass"
];

const hits = [];

async function walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(full);
      continue;
    }
    if (!/\.(swift|pbxproj|plist|json)$/i.test(entry.name)) {
      continue;
    }
    const text = await readFile(full, "utf8");
    for (const term of forbidden) {
      if (text.includes(term)) {
        hits.push(`${path.relative(root, full)} contains ${term}`);
      }
    }
  }
}

for (const dir of scanDirs) {
  await walk(path.join(root, dir));
}

if (hits.length > 0) {
  console.error("Private Apple API guard failed:");
  for (const hit of hits) {
    console.error(`- ${hit}`);
  }
  process.exit(1);
}

console.log("Private Apple API guard passed.");
