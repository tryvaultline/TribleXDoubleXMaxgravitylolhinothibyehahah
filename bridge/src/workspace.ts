import { readdir, stat } from "node:fs/promises";
import path from "node:path";
import { WorkspaceRoot } from "./schemas.js";

export class WorkspaceError extends Error {
  constructor(message: string, readonly code: "ROOT_NOT_FOUND" | "PATH_TRAVERSAL" | "NOT_DIRECTORY") {
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

  async createFolder(rootId: string, relativePath: string, folderName: string): Promise<string> {
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
}
