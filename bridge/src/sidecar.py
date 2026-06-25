import sys
import os
import json
import asyncio
import sqlite3
import uuid
import shutil
import pathlib
import traceback

# Ensure stdout is in UTF-8 mode
sys.stdout.reconfigure(encoding='utf-8')

# Try importing the SDK
try:
    from google.antigravity import agent as antigravity_agent
    from google.antigravity.connections.local import local_connection_config
    from google.antigravity.connections.local import local_connection
    from google.antigravity.hooks import policy
    SDK_AVAILABLE = True
except ImportError:
    SDK_AVAILABLE = False

DB_PATH = os.path.join("..", ".local", "maxgravity.db")

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            space_id TEXT NOT NULL,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    conn.commit()
    conn.close()

def run_diagnose():
    # Diagnostics check
    python_available = True
    venv_active = sys.prefix != sys.base_prefix
    sdk_installed = SDK_AVAILABLE
    
    # Try finding localharness
    harness_path = None
    try:
        if sdk_installed:
            harness_path = local_connection._get_default_binary_path_external()
    except Exception:
        pass
    cli_available = harness_path is not None and os.path.exists(harness_path)
    
    auth_ready = "GEMINI_API_KEY" in os.environ or "VERTEX_API_KEY" in os.environ
    workspace_ready = True  # Local disk access is always ready
    sidecar_health = sdk_installed and cli_available
    
    return {
        "python_available": python_available,
        "venv_active": venv_active,
        "sdk_installed": sdk_installed,
        "cli_available": cli_available,
        "auth_ready": auth_ready,
        "workspace_ready": workspace_ready,
        "sidecar_health": sidecar_health,
        "harness_path": harness_path
    }

async def run_chat_task(conv_id, prompt, workspace_root, api_key):
    try:
        # Determine API key
        key = api_key or os.environ.get("GEMINI_API_KEY")
        if not key:
            # Return error event if no API key is set
            send_event({
                "type": "task.stage",
                "taskId": conv_id,
                "stage": "Task failed",
                "detail": "Missing GEMINI_API_KEY. Configure it on your computer.",
                "emittedAt": ""
            })
            return

        # Prepare workspace paths
        normalized_workspace = str(pathlib.Path(workspace_root).resolve())
        
        # Setup config
        config = local_connection_config.LocalAgentConfig(
            system_instructions="You are Maxgravity's autonomous coding assistant.",
            workspaces=[normalized_workspace],
            policies=[policy.allow_all()],
            api_key=key
        )
        
        # Update DB state
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE conversations SET status = 'Planning changes', updated_at = datetime('now') WHERE id = ?",
            (conv_id,)
        )
        conn.commit()
        conn.close()

        # Send initial stage event
        send_event({
            "type": "task.stage",
            "taskId": conv_id,
            "stage": "Planning changes",
            "detail": "Initializing Antigravity Agent and checking workspace...",
            "emittedAt": ""
        })

        agent = antigravity_agent.Agent(config)
        async with agent:
            # Send prompt to connection
            await agent.conversation.connection.send(prompt)
            
            # Read streaming steps
            async for step in agent.conversation.connection.receive_steps():
                # Map step details to safe visual stages
                stage = "Planning changes"
                detail = step.content or ""
                
                # Check tool calls
                if step.tool_calls:
                    tc = step.tool_calls[0]
                    name = tc.name
                    args = tc.args
                    
                    if name in ("view_file", "list_directory", "find_file", "search_directory"):
                        stage = "Reading files"
                        detail = f"Reading {args.get('path', args.get('file_path', ''))}"
                    elif name in ("edit_file", "create_file"):
                        stage = "Updating files"
                        detail = f"Modifying {args.get('TargetFile', args.get('path', ''))}"
                    elif name == "run_command":
                        cmd = args.get("CommandLine", "")
                        if "test" in cmd or "lint" in cmd:
                            stage = "Running tests"
                        else:
                            stage = "Running commands"
                        detail = f"Running: {cmd[:60]}"
                    elif name == "invoke_subagent":
                        stage = "Planning changes"
                        detail = "Invoking developer subagent..."
                    elif name == "finish":
                        stage = "Task completed"
                        detail = "Agent completed the requested changes."
                
                if step.status == local_connection.types.StepStatus.WAITING_FOR_USER:
                    stage = "Awaiting approval"
                    detail = "Awaiting user response..."
                
                if step.error:
                    stage = "Task failed"
                    detail = step.error

                # Send live event
                send_event({
                    "type": "task.stage",
                    "taskId": conv_id,
                    "stage": stage,
                    "detail": detail[:300],
                    "emittedAt": ""
                })

                # If there are command outputs
                if step.type == local_connection.types.StepType.TOOL_CALL and step.tool_calls[0].name == "run_command":
                    # We can stream command outputs if available, but the harness handles execution results.
                    pass

        # Update final state
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE conversations SET status = 'Task completed', updated_at = datetime('now') WHERE id = ?",
            (conv_id,)
        )
        conn.commit()
        conn.close()

    except Exception as e:
        tb = traceback.format_exc()
        send_event({
            "type": "task.stage",
            "taskId": conv_id,
            "stage": "Task failed",
            "detail": f"Execution error: {str(e)}",
            "emittedAt": ""
        })
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE conversations SET status = 'Task failed', updated_at = datetime('now') WHERE id = ?",
            (conv_id,)
        )
        conn.commit()
        conn.close()

def send_response(req_id, result=None, error=None):
    resp = {"jsonrpc": "2.0", "id": req_id}
    if error:
        resp["error"] = error
    else:
        resp["result"] = result
    sys.stdout.write(json.dumps(resp) + "\n")
    sys.stdout.flush()

def send_event(event):
    sys.stdout.write(json.dumps({
        "jsonrpc": "2.0",
        "method": "event",
        "params": event
    }) + "\n")
    sys.stdout.flush()

async def main():
    init_db()
    
    # Read from stdin asynchronously
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)

    while True:
        line = await reader.readline()
        if not line:
            break
        
        try:
            req = json.loads(line.decode('utf-8'))
            req_id = req.get("id")
            method = req.get("method")
            params = req.get("params", {})

            if method == "diagnose":
                diagnostics = run_diagnose()
                send_response(req_id, result=diagnostics)

            elif method == "create_conversation":
                space_id = params.get("spaceId")
                title = params.get("title", "New task")
                conv_id = params.get("conversationId") or str(uuid.uuid4())
                
                conn = sqlite3.connect(DB_PATH)
                cursor = conn.cursor()
                cursor.execute(
                    "INSERT INTO conversations (id, space_id, title, status, created_at, updated_at) VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))",
                    (conv_id, space_id, title, "Planning changes")
                )
                conn.commit()
                conn.close()

                send_response(req_id, result={
                    "conversationId": conv_id,
                    "spaceId": space_id,
                    "title": title,
                    "status": "Planning changes"
                })

            elif method == "chat":
                conv_id = params.get("conversationId")
                prompt = params.get("prompt")
                workspace_root = params.get("workspaceRoot")
                api_key = params.get("apiKey")

                # Run chat in the background
                asyncio.create_task(run_chat_task(conv_id, prompt, workspace_root, api_key))
                send_response(req_id, result={"status": "started"})

            elif method == "list_conversations":
                space_id = params.get("spaceId")
                conn = sqlite3.connect(DB_PATH)
                cursor = conn.cursor()
                if space_id:
                    cursor.execute("SELECT id, space_id, title, status, created_at, updated_at FROM conversations WHERE space_id = ? ORDER BY updated_at DESC", (space_id,))
                else:
                    cursor.execute("SELECT id, space_id, title, status, created_at, updated_at FROM conversations ORDER BY updated_at DESC")
                
                rows = cursor.fetchall()
                conn.close()

                chats = [{
                    "id": r[0],
                    "spaceId": r[1],
                    "title": r[2],
                    "status": r[3],
                    "createdAt": r[4],
                    "updatedAt": r[5]
                } for r in rows]
                send_response(req_id, result=chats)

            else:
                send_response(req_id, error={"code": -32601, "message": f"Method {method} not found"})

        except Exception as e:
            sys.stderr.write(f"Error handling request: {str(e)}\n")
            sys.stderr.flush()

if __name__ == "__main__":
    asyncio.run(main())
