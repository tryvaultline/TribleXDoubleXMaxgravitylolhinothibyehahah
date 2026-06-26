import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { WorkspaceRoot } from "./schemas.js";

export class WorkspaceError extends Error {
  constructor(message: string, readonly code: "ROOT_NOT_FOUND" | "PATH_TRAVERSAL" | "NOT_DIRECTORY" | "INVALID_NAME" | "FILE_TOO_LARGE") {
    super(message);
  }
}

export interface WorkspaceNode {
  name: string;
  path: string;
  isDirectory: boolean;
}

export class WorkspaceBrowser {
  constructor(private readonly roots: WorkspaceRoot[]) {}

  listRoots(): WorkspaceRoot[] {
    return this.roots;
  }

  resolve(rootId: string, relativePath = "."): string {
    const root = this.roots.find((candidate) => candidate.id === rootId);
    if (!root) {
      throw new WorkspaceError("Workspace root was not found.", "ROOT_NOT_FOUND");
    }

    const rootPath = path.resolve(root.path);
    const target = path.resolve(rootPath, relativePath);
    const relative = path.relative(rootPath, target);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
      throw new WorkspaceError("Requested path escapes the approved workspace root.", "PATH_TRAVERSAL");
    }
    return target;
  }

  async browse(rootId: string, relativePath = "."): Promise<WorkspaceNode[]> {
    const target = this.resolve(rootId, relativePath);
    const targetStat = await stat(target);
    if (!targetStat.isDirectory()) {
      throw new WorkspaceError("Requested path is not a directory.", "NOT_DIRECTORY");
    }

    const entries = await readdir(target, { withFileTypes: true });
    return entries
      .filter((entry) => !entry.name.startsWith("."))
      .slice(0, 300)
      .map((entry) => ({
        name: entry.name,
        path: path.join(relativePath, entry.name),
        isDirectory: entry.isDirectory()
      }));
  }

  async readTextFile(rootId: string, relativePath: string): Promise<{ path: string; content: string }> {
    const target = this.resolve(rootId, relativePath);
    const targetStat = await stat(target);
    if (!targetStat.isFile()) {
      throw new WorkspaceError("Requested path is not a file.", "NOT_DIRECTORY");
    }

    const content = await readFile(target, "utf8");
    return { path: relativePath, content };
  }

  async createFolder(rootId: string, relativePath: string, folderName: string): Promise<string> {
    assertSafeLeafName(folderName);
    const parent = this.resolve(rootId, relativePath);
    const target = path.join(parent, folderName);
    const root = this.roots.find((candidate) => candidate.id === rootId)!;
    const rootPath = path.resolve(root.path);
    const relative = path.relative(rootPath, target);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
      throw new WorkspaceError("Requested path escapes the approved workspace root.", "PATH_TRAVERSAL");
    }
    await import("node:fs/promises").then(fs => fs.mkdir(target, { recursive: true }));
    return relative;
  }

  async writeBinaryFile(rootId: string, relativePath: string, fileName: string, content: Buffer): Promise<string> {
    assertSafeLeafName(fileName);
    if (content.byteLength > 10 * 1024 * 1024) {
      throw new WorkspaceError("File is too large for a mobile workspace import.", "FILE_TOO_LARGE");
    }
    const parent = this.resolve(rootId, relativePath);
    const target = path.join(parent, fileName);
    const root = this.roots.find((candidate) => candidate.id === rootId)!;
    const rootPath = path.resolve(root.path);
    const relative = path.relative(rootPath, target);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
      throw new WorkspaceError("Requested path escapes the approved workspace root.", "PATH_TRAVERSAL");
    }
    await writeFile(target, content);
    return relative;
  }
}

function assertSafeLeafName(value: string): void {
  const trimmed = value.trim();
  if (!trimmed || trimmed === "." || trimmed === ".." || /[\\/:*?"<>|\u0000-\u001F]/.test(trimmed)) {
    throw new WorkspaceError("File or folder name is invalid.", "INVALID_NAME");
  }
}
