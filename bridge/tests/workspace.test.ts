import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { WorkspaceBrowser } from "../src/workspace.js";

describe("WorkspaceBrowser", () => {
  it("lists only files inside an approved root", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "mg-root-"));
    await mkdir(path.join(root, "src"));
    await writeFile(path.join(root, "README.md"), "hello", "utf8");
    const browser = new WorkspaceBrowser([{ id: "root", name: "Root", path: root }]);

    const nodes = await browser.browse("root");

    expect(nodes.map((node) => node.name).sort()).toEqual(["README.md", "src"]);
  });

  it("blocks path traversal outside approved roots", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "mg-root-"));
    const browser = new WorkspaceBrowser([{ id: "root", name: "Root", path: root }]);

    expect(() => browser.resolve("root", "../outside")).toThrow(/escapes/);
  });
});
