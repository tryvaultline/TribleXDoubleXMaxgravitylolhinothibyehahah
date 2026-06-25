import { spawn, execSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";
import { BridgeCapability } from "./schemas.js";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, "..", "..");
const localDir = join(projectRoot, "bridge", ".local");

export interface AntigravityAdapter {
  getCapabilities(): Promise<BridgeCapability[]>;
  diagnose(): Promise<any>;
  createConversation(spaceId: string, title: string, conversationId?: string): Promise<any>;
  chat(conversationId: string, prompt: string, workspaceRoot: string, apiKey?: string): Promise<any>;
  listConversations(spaceId?: string): Promise<any>;
  onEvent(callback: (event: any) => void): () => void;
}

export class UnsupportedCapabilityError extends Error {
  constructor(capability: string) {
    super(`${capability} is not available through a verified official Antigravity CLI or SDK contract yet.`);
    this.name = "UnsupportedCapabilityError";
  }
}

interface LocalTask {
  id: string;
  realId?: string;
  spaceId: string;
  title: string;
  status: string;
  createdAt: string;
  updatedAt: string;
}

export class AntigravityCliAccountAdapter implements AntigravityAdapter {
  private readonly agentApiBat = "C:\\Users\\kuroi\\.gemini\\antigravity\\bin\\agentapi.bat";
  private readonly realLogDir = "C:\\Users\\kuroi\\AppData\\Roaming\\Antigravity\\logs";
  private readonly localDir = localDir;
  private readonly tasksFile = join(localDir, "tasks.json");
  private eventCallbacks: ((event: any) => void)[] = [];
  private localToRealMap = new Map<string, string>();
  private realToLocalMap = new Map<string, string>();
  private pollInterval: NodeJS.Timeout | null = null;

  constructor() {
    mkdirSync(this.localDir, { recursive: true });
    this.loadMaps();
    this.startPolling();
  }

  private loadMaps() {
    const tasks = this.loadTasks();
    for (const t of tasks) {
      if (t.realId) {
        this.localToRealMap.set(t.id, t.realId);
        this.realToLocalMap.set(t.realId, t.id);
      }
    }
  }

  private loadTasks(): LocalTask[] {
    if (!existsSync(this.tasksFile)) {
      return [];
    }
    try {
      return JSON.parse(readFileSync(this.tasksFile, "utf8"));
    } catch {
      return [];
    }
  }

  private saveTasks(tasks: LocalTask[]) {
    writeFileSync(this.tasksFile, JSON.stringify(tasks, null, 2));
  }

  private saveTask(task: LocalTask) {
    const tasks = this.loadTasks();
    const idx = tasks.findIndex(t => t.id === task.id);
    if (idx !== -1) {
      tasks[idx] = task;
    } else {
      tasks.push(task);
    }
    this.saveTasks(tasks);
  }

  private updateTaskStatus(id: string, status: string) {
    const tasks = this.loadTasks();
    const task = tasks.find(t => t.id === id);
    if (task) {
      task.status = status;
      task.updatedAt = new Date().toISOString();
      this.saveTask(task);
    }
  }

  public discoverSession(): { token: string | null; address: string | null } {
    let token = process.env.ANTIGRAVITY_CSRF_TOKEN || null;
    let address = process.env.ANTIGRAVITY_LS_ADDRESS || null;

    if (token && address) {
      return { token, address };
    }

    // Fallback to logs
    const mainLogPath = join(this.realLogDir, "main.log");
    if (existsSync(mainLogPath)) {
      try {
        const content = readFileSync(mainLogPath, "utf8");
        const lines = content.split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
          const line = lines[i];
          if (line.includes("language_server.exe") && line.includes("--csrf_token")) {
            const match = line.match(/--csrf_token\s+([a-f0-9-]+)/);
            if (match) {
              token = match[1];
              break;
            }
          }
        }
      } catch (err) {
        console.error("Failed to read main.log for token:", err);
      }
    }

    const lsLogPath = join(this.realLogDir, "language_server.log");
    if (existsSync(lsLogPath)) {
      try {
        const content = readFileSync(lsLogPath, "utf8");
        const lines = content.split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
          const line = lines[i];
          if (line.includes("Language server listening on random port at") && line.includes("for HTTP")) {
            const match = line.match(/Language server listening on random port at\s+(\d+)\s+for HTTP/);
            if (match) {
              address = `localhost:${match[1]}`;
              break;
            }
          }
        }
      } catch (err) {
        console.error("Failed to read language_server.log for address:", err);
      }
    }

    return { token, address };
  }

  private async checkAuth(session: { token: string; address: string }): Promise<boolean> {
    try {
      execSync(`"${this.agentApiBat}" get-conversation-metadata dummy-id`, {
        env: {
          ...process.env,
          ANTIGRAVITY_LS_ADDRESS: session.address,
          ANTIGRAVITY_CSRF_TOKEN: session.token
        },
        stdio: ["ignore", "pipe", "pipe"]
      });
      return true;
    } catch (err: any) {
      const errOutput = err.stdout?.toString() || err.stderr?.toString() || err.message || "";
      if (errOutput.includes("trajectory not found")) {
        return true;
      }
      return false;
    }
  }

  onEvent(callback: (event: any) => void): () => void {
    this.eventCallbacks.push(callback);
    return () => {
      this.eventCallbacks = this.eventCallbacks.filter(cb => cb !== callback);
    };
  }

  async getCapabilities(): Promise<BridgeCapability[]> {
    const isInstalled = existsSync(this.agentApiBat);
    const session = this.discoverSession();
    const authenticated = isInstalled && session.token && session.address
      ? await this.checkAuth(session as { token: string; address: string })
      : false;

    return [
      {
        id: "antigravity.official-interface",
        title: "Official Antigravity CLI",
        status: isInstalled ? "Live" : "Unsupported",
        notes: isInstalled
          ? "Antigravity CLI (agentapi) is installed and verified."
          : "Antigravity CLI is missing."
      },
      {
        id: "tasks.create",
        title: "Create Antigravity task",
        status: authenticated ? "Live" : "Unsupported",
        notes: authenticated
          ? "Task creation via Antigravity CLI is ready."
          : "Local Antigravity account is not authenticated."
      },
      {
        id: "tasks.live-events",
        title: "Live Antigravity task events",
        status: isInstalled ? "Live" : "Unsupported",
        notes: "Task event streaming mirrors active agent steps from transcript logs."
      },
      {
        id: "approvals.resolve",
        title: "Resolve approval requests",
        status: "Unsupported",
        notes: "Requires active agent policies configurations."
      }
    ];
  }

  async diagnose(): Promise<any> {
    const isInstalled = existsSync(this.agentApiBat);
    const session = this.discoverSession();
    const authenticated = isInstalled && session.token && session.address
      ? await this.checkAuth(session as { token: string; address: string })
      : false;

    return {
      cli_available: isInstalled,
      auth_ready: authenticated,
      workspace_ready: true,
      bridge_health: true
    };
  }

  async createConversation(spaceId: string, title: string, conversationId?: string): Promise<any> {
    const localId = conversationId || crypto.randomUUID();
    const task: LocalTask = {
      id: localId,
      spaceId,
      title,
      status: "Starting Antigravity task",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    this.saveTask(task);
    return {
      conversationId: localId,
      spaceId,
      title,
      status: "Starting Antigravity task"
    };
  }

  async chat(conversationId: string, prompt: string, workspaceRoot: string, _apiKey?: string): Promise<any> {
    // If we already have a real conversation ID mapped, treat this as a follow-up send-message
    if (this.localToRealMap.has(conversationId)) {
      const realId = this.localToRealMap.get(conversationId)!;
      const session = this.discoverSession();
      if (!session.token || !session.address) {
        throw new Error("Antigravity session not found. Please ensure Antigravity is running.");
      }

      const child = spawn(this.agentApiBat, ["send-message", realId, prompt], {
        cwd: workspaceRoot,
        env: {
          ...process.env,
          ANTIGRAVITY_LS_ADDRESS: session.address,
          ANTIGRAVITY_CSRF_TOKEN: session.token
        },
        shell: process.platform === "win32"
      });
      child.on("close", (code) => {
        if (code !== 0) {
          console.error(`agentapi send-message exited with code ${code}`);
        }
      });
      return { status: "sent" };
    }

    // Otherwise, create a new conversation in background
    const session = this.discoverSession();
    if (!session.token || !session.address) {
      throw new Error("Antigravity session not found. Please ensure Antigravity is running.");
    }

    const child = spawn(this.agentApiBat, ["new-conversation", prompt], {
      cwd: workspaceRoot,
      env: {
        ...process.env,
        ANTIGRAVITY_LS_ADDRESS: session.address,
        ANTIGRAVITY_CSRF_TOKEN: session.token
      },
      shell: process.platform === "win32"
    });

    let output = "";
    child.stdout.on("data", (data) => {
      output += data.toString();
    });

    child.on("close", (code) => {
      if (code !== 0) {
        console.error(`agentapi new-conversation exited with code ${code}`);
        this.updateTaskStatus(conversationId, "Task failed");
        this.emitStage(conversationId, "Task failed", "Execution command failed.");
        return;
      }

      try {
        const payload = JSON.parse(output.trim());
        const realId = payload.response?.newConversation?.conversationId;
        if (realId) {
          console.log(`Mapped local conversation ${conversationId} to real conversation ${realId}`);
          this.localToRealMap.set(conversationId, realId);
          this.realToLocalMap.set(realId, conversationId);

          const tasks = this.loadTasks();
          const task = tasks.find(t => t.id === conversationId);
          if (task) {
            task.realId = realId;
            this.saveTask(task);
          }
        }
      } catch (err) {
        console.error("Failed to parse new-conversation output:", output, err);
        this.updateTaskStatus(conversationId, "Task failed");
        this.emitStage(conversationId, "Task failed", "Failed to parse session ID.");
      }
    });

    return { status: "started" };
  }

  async listConversations(spaceId?: string): Promise<any> {
    const tasks = this.loadTasks();
    if (spaceId) {
      return tasks.filter(t => t.spaceId === spaceId);
    }
    return tasks;
  }

  private emitStage(taskId: string, stage: string, detail: string) {
    this.eventCallbacks.forEach(cb => cb({
      type: "task.stage",
      taskId,
      stage,
      detail: detail.slice(0, 300),
      emittedAt: new Date().toISOString()
    }));
  }

  private startPolling() {
    if (this.pollInterval) return;

    this.pollInterval = setInterval(() => {
      const tasks = this.loadTasks();
      const activeTasks = tasks.filter(t => t.status !== "Task completed" && t.status !== "Task failed");
      
      for (const task of activeTasks) {
        if (!task.realId) continue;
        
        const logFile = `C:\\Users\\kuroi\\.gemini\\antigravity\\brain\\${task.realId}\\.system_generated\\logs\\transcript.jsonl`;
        if (!existsSync(logFile)) continue;

        try {
          const content = readFileSync(logFile, "utf8").trim();
          if (!content) continue;

          const lines = content.split("\n");
          const steps = lines.map(l => JSON.parse(l));
          if (steps.length === 0) continue;

          const lastStep = steps[steps.length - 1];
          let stage = "Planning changes";
          let detail = lastStep.content || "";

          if (lastStep.status === "ERROR" || lastStep.type === "ERROR" || (lastStep.content && lastStep.content.includes("error:"))) {
            stage = "Task failed";
            detail = lastStep.content || "An error occurred during execution.";
          } else if (lastStep.type === "PLANNER_RESPONSE") {
            if (lastStep.tool_calls && lastStep.tool_calls.length > 0) {
              const tc = lastStep.tool_calls[0];
              const name = tc.name;
              const args = tc.args || {};
              
              if (name === "ask_permission") {
                stage = "Awaiting approval";
                detail = "Awaiting your approval to proceed...";
              } else if (name === "run_command") {
                const cmd = args.CommandLine || "";
                if (cmd.includes("test") || cmd.includes("lint") || cmd.includes("vitest")) {
                  stage = "Running tests";
                } else {
                  stage = "Running command";
                }
                detail = `Executing: ${cmd}`;
              } else if (["view_file", "list_dir", "grep_search", "read_file", "list_directory"].includes(name)) {
                stage = "Reading workspace";
                detail = `Reading ${args.AbsolutePath || args.DirectoryPath || args.SearchPath || ""}`;
              } else if (["write_to_file", "replace_file_content", "multi_replace_file_content", "write_file", "edit_file", "create_file"].includes(name)) {
                stage = "Updating files";
                detail = `Updating ${args.TargetFile || args.path || ""}`;
              } else {
                stage = "Planning changes";
                detail = lastStep.content || "Thinking...";
              }
            } else {
              stage = "Task completed";
              detail = lastStep.content || "Task finished successfully.";
            }
          } else {
            stage = "Planning changes";
            detail = "Processing step results...";
          }

          if (task.status !== stage) {
            console.log(`Task ${task.id} (${task.title}) stage transition: ${task.status} -> ${stage}`);
            this.updateTaskStatus(task.id, stage);
            this.emitStage(task.id, stage, detail);
          }
        } catch (err) {
          console.error(`Failed to poll logs for task ${task.id}:`, err);
        }
      }
    }, 1500);
  }

  public stop() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }
}
