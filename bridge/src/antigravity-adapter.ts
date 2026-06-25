import { spawn, ChildProcess } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";
import { BridgeCapability } from "./schemas.js";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, "..", "..");

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

export class PythonSidecarAdapter implements AntigravityAdapter {
  private child!: ChildProcess;
  private reqIdCounter = 0;
  private pendingRequests = new Map<number, { resolve: (val: any) => void; reject: (err: any) => void }>();
  private eventCallbacks: ((event: any) => void)[] = [];
  private venvPython: string;

  constructor() {
    this.venvPython = join(projectRoot, "bridge", ".local", "..", ".venv", "Scripts", "python.exe");
    this.startSidecar();
  }

  private startSidecar() {
    const sidecarPath = join(projectRoot, "bridge", "src", "sidecar.py");
    
    // Spawn Python sidecar subprocess using venv Python
    this.child = spawn(this.venvPython, [sidecarPath], {
      cwd: projectRoot,
      env: { ...process.env }
    });

    const rl = createInterface({
      input: this.child.stdout!,
      crlfDelay: Infinity
    });

    rl.on("line", (line) => {
      try {
        const payload = JSON.parse(line);
        if (payload.method === "event") {
          // Broadcast notify event
          this.eventCallbacks.forEach(cb => cb(payload.params));
        } else if (payload.id !== undefined) {
          const promise = this.pendingRequests.get(payload.id);
          if (promise) {
            this.pendingRequests.delete(payload.id);
            if (payload.error) {
              promise.reject(new Error(payload.error.message || "Sidecar Error"));
            } else {
              promise.resolve(payload.result);
            }
          }
        }
      } catch (err) {
        console.error("Failed to parse sidecar line:", line, err);
      }
    });

    this.child.stderr!.on("data", (data) => {
      console.error(`[Sidecar Stderr] ${data.toString().trim()}`);
    });

    this.child.on("close", (code) => {
      console.warn(`Sidecar process closed with code ${code}. Restarting...`);
      // Reject all pending
      this.pendingRequests.forEach(p => p.reject(new Error("Sidecar process terminated")));
      this.pendingRequests.clear();
      setTimeout(() => this.startSidecar(), 2000);
    });
  }

  private sendRequest(method: string, params: any = {}): Promise<any> {
    const id = ++this.reqIdCounter;
    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });
      const payload = JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n";
      this.child.stdin!.write(payload);
    });
  }

  onEvent(callback: (event: any) => void): () => void {
    this.eventCallbacks.push(callback);
    return () => {
      this.eventCallbacks = this.eventCallbacks.filter(cb => cb !== callback);
    };
  }

  async getCapabilities(): Promise<BridgeCapability[]> {
    const diagnostics = await this.diagnose().catch(() => null);
    const sdkInstalled = diagnostics?.sdk_installed ? "Live" : "Unsupported";
    const cliAvailable = diagnostics?.cli_available ? "Live" : "Unsupported";
    
    return [
      {
        id: "antigravity.official-interface",
        title: "Official Antigravity CLI / SDK",
        status: sdkInstalled,
        notes: diagnostics?.sdk_installed 
          ? "Google Antigravity SDK is installed and verified in venv." 
          : "google-antigravity library is missing in venv."
      },
      {
        id: "tasks.create",
        title: "Create Antigravity task",
        status: sdkInstalled,
        notes: "Real task launch is connected to the Python sidecar."
      },
      {
        id: "tasks.live-events",
        title: "Live Antigravity task events",
        status: cliAvailable,
        notes: "WebSocket event streaming mirrors active agent steps."
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
    return this.sendRequest("diagnose");
  }

  async createConversation(spaceId: string, title: string, conversationId?: string): Promise<any> {
    return this.sendRequest("create_conversation", { spaceId, title, conversationId });
  }

  async chat(conversationId: string, prompt: string, workspaceRoot: string, apiKey?: string): Promise<any> {
    return this.sendRequest("chat", { conversationId, prompt, workspaceRoot, apiKey });
  }

  async listConversations(spaceId?: string): Promise<any> {
    return this.sendRequest("list_conversations", { spaceId });
  }
}
