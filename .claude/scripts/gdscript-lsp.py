#!/usr/bin/env python3
"""
Direct GDScript LSP client — bypasses Claude Code's LSP subsystem.
Talks to Godot's built-in LSP server on TCP port 6005.

Usage:
  gdscript-lsp.py hover <file> <line> <char>
  gdscript-lsp.py diagnostics <file>
  gdscript-lsp.py definition <file> <line> <char>
  gdscript-lsp.py references <file> <line> <char>
  gdscript-lsp.py symbols <file>
"""

import json
import socket
import sys
import os
import subprocess
from pathlib import Path

PORT = int(os.environ.get("GODOT_LSP_PORT", "6005"))
HOST = "localhost"
PROJECT_ROOT = None

# Find project root
for candidate in [os.environ.get("CLAUDE_PROJECT_DIR", ""), os.getcwd()]:
    if candidate:
        p = Path(candidate)
        while p != p.parent:
            if (p / "project.godot").exists():
                PROJECT_ROOT = str(p.resolve())
                break
            p = p.parent
        if PROJECT_ROOT:
            break

if not PROJECT_ROOT:
    for p in ["/var/tumu/workspace", "/Users/jeremy/dev/dax/test123"]:
        if Path(p).joinpath("project.godot").exists():
            PROJECT_ROOT = str(Path(p).resolve())
            break

if not PROJECT_ROOT:
    print("Error: Cannot find project.godot", file=sys.stderr)
    sys.exit(1)


def file_uri(path: str) -> str:
    """Convert a file path to a file:// URI."""
    if not os.path.isabs(path):
        path = os.path.join(PROJECT_ROOT, path)
    return f"file://{os.path.realpath(path)}"


def send_lsp(sock: socket.socket, method: str, params: dict, msg_id: int) -> None:
    """Send a JSON-RPC request over LSP protocol."""
    body = json.dumps({"jsonrpc": "2.0", "id": msg_id, "method": method, "params": params})
    header = f"Content-Length: {len(body)}\r\n\r\n"
    sock.sendall((header + body).encode())


def send_notification(sock: socket.socket, method: str, params: dict) -> None:
    """Send a JSON-RPC notification (no id, no response expected)."""
    body = json.dumps({"jsonrpc": "2.0", "method": method, "params": params})
    header = f"Content-Length: {len(body)}\r\n\r\n"
    sock.sendall((header + body).encode())


def recv_lsp(sock: socket.socket, timeout: float = 10.0) -> list[dict]:
    """Receive one or more LSP messages. Returns list of parsed JSON objects."""
    sock.settimeout(timeout)
    buf = b""
    messages = []
    try:
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
            # Parse all complete messages from buffer
            while True:
                # Find Content-Length header
                header_end = buf.find(b"\r\n\r\n")
                if header_end == -1:
                    break
                header = buf[:header_end].decode()
                content_length = None
                for line in header.split("\r\n"):
                    if line.lower().startswith("content-length:"):
                        content_length = int(line.split(":")[1].strip())
                        break
                if content_length is None:
                    break
                body_start = header_end + 4
                body_end = body_start + content_length
                if len(buf) < body_end:
                    break  # Incomplete body, wait for more data
                body = buf[body_start:body_end].decode()
                buf = buf[body_end:]
                msg = json.loads(body)
                messages.append(msg)
                # If we got a response (has 'id'), we can return
                if "id" in msg:
                    return messages
    except socket.timeout:
        pass
    return messages


def ensure_godot_lsp():
    """Start Godot headless LSP if not running."""
    try:
        s = socket.create_connection((HOST, PORT), timeout=1)
        s.close()
        return True
    except (ConnectionRefusedError, socket.timeout, OSError):
        pass

    # Try to start it
    godot = "/Applications/Godot.app/Contents/MacOS/Godot"
    if not os.path.exists(godot):
        print("Error: Godot not found at expected path", file=sys.stderr)
        return False

    subprocess.Popen(
        [godot, "--editor", "--headless", "--lsp-port", str(PORT), "--path", PROJECT_ROOT],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    # Wait for port
    for _ in range(40):
        try:
            s = socket.create_connection((HOST, PORT), timeout=0.5)
            s.close()
            return True
        except (ConnectionRefusedError, socket.timeout, OSError):
            import time
            time.sleep(0.5)

    print("Error: Godot LSP failed to start", file=sys.stderr)
    return False


def lsp_session(operation: str, file_path: str, line: int = 0, char: int = 0):
    """Run a full LSP session: initialize, open file, perform operation, return result."""
    if not ensure_godot_lsp():
        return None

    sock = socket.create_connection((HOST, PORT), timeout=10)
    uri = file_uri(file_path)

    # 1. Initialize
    send_lsp(sock, "initialize", {
        "processId": os.getpid(),
        "rootUri": f"file://{PROJECT_ROOT}",
        "capabilities": {},
    }, msg_id=1)
    msgs = recv_lsp(sock)

    # 2. Initialized notification
    send_notification(sock, "initialized", {})

    # 3. Open the file
    try:
        abs_path = file_path if os.path.isabs(file_path) else os.path.join(PROJECT_ROOT, file_path)
        text = Path(abs_path).read_text()
    except FileNotFoundError:
        print(f"Error: File not found: {file_path}", file=sys.stderr)
        sock.close()
        return None

    send_notification(sock, "textDocument/didOpen", {
        "textDocument": {"uri": uri, "languageId": "gdscript", "version": 1, "text": text},
    })

    # Small delay to let server process the file
    import time
    time.sleep(0.5)

    # 4. Perform operation
    msg_id = 2
    if operation == "hover":
        send_lsp(sock, "textDocument/hover", {
            "textDocument": {"uri": uri},
            "position": {"line": line, "character": char},
        }, msg_id)
    elif operation == "definition":
        send_lsp(sock, "textDocument/definition", {
            "textDocument": {"uri": uri},
            "position": {"line": line, "character": char},
        }, msg_id)
    elif operation == "references":
        send_lsp(sock, "textDocument/references", {
            "textDocument": {"uri": uri},
            "position": {"line": line, "character": char},
            "context": {"includeDeclaration": True},
        }, msg_id)
    elif operation == "symbols":
        send_lsp(sock, "textDocument/documentSymbol", {
            "textDocument": {"uri": uri},
        }, msg_id)
    elif operation == "diagnostics":
        # Diagnostics are pushed, not requested. Wait for them after didOpen.
        time.sleep(2)
        # Collect any notifications that arrived
        msgs = recv_lsp(sock, timeout=3)
        diags = []
        for m in msgs:
            if m.get("method") == "textDocument/publishDiagnostics":
                for d in m.get("params", {}).get("diagnostics", []):
                    r = d.get("range", {}).get("start", {})
                    diags.append({
                        "line": r.get("line", 0) + 1,
                        "severity": ["", "Error", "Warning", "Info", "Hint"][d.get("severity", 0)],
                        "message": d.get("message", ""),
                    })
        sock.close()
        return diags
    else:
        print(f"Unknown operation: {operation}", file=sys.stderr)
        sock.close()
        return None

    # 5. Read response
    msgs = recv_lsp(sock)
    result = None
    for m in msgs:
        if m.get("id") == msg_id:
            result = m.get("result")
            break

    sock.close()
    return result


def format_hover(result):
    if not result:
        return "No hover info"
    contents = result.get("contents", "")
    if isinstance(contents, dict):
        return contents.get("value", str(contents))
    if isinstance(contents, list):
        return "\n".join(c.get("value", str(c)) if isinstance(c, dict) else str(c) for c in contents)
    return str(contents)


def format_definition(result):
    if not result:
        return "No definition found"
    if isinstance(result, list):
        lines = []
        for loc in result:
            uri = loc.get("uri", loc.get("targetUri", ""))
            r = loc.get("range", loc.get("targetRange", {})).get("start", {})
            path = uri.replace(f"file://{PROJECT_ROOT}/", "").replace("file://", "")
            lines.append(f"{path}:{r.get('line', 0) + 1}:{r.get('character', 0) + 1}")
        return "\n".join(lines)
    return str(result)


def format_symbols(result):
    if not result:
        return "No symbols"
    lines = []
    kind_names = {1: "File", 2: "Module", 3: "Namespace", 5: "Class", 6: "Method",
                  7: "Property", 8: "Field", 9: "Constructor", 10: "Enum", 12: "Function",
                  13: "Variable", 14: "Constant", 23: "Struct", 24: "Event"}
    for s in result:
        kind = kind_names.get(s.get("kind", 0), f"Kind({s.get('kind')})")
        r = s.get("range", {}).get("start", {})
        name = s.get("name", "?")
        lines.append(f"  L{r.get('line', 0) + 1:4d}  {kind:12s}  {name}")
        for child in s.get("children", []):
            cr = child.get("range", {}).get("start", {})
            ck = kind_names.get(child.get("kind", 0), f"Kind({child.get('kind')})")
            lines.append(f"  L{cr.get('line', 0) + 1:4d}    {ck:10s}  {child.get('name', '?')}")
    return "\n".join(lines)


def format_diagnostics(result):
    if not result:
        return "No diagnostics (clean)"
    lines = []
    for d in result:
        lines.append(f"  L{d['line']:4d}  [{d['severity']}] {d['message']}")
    return "\n".join(lines) if lines else "No diagnostics (clean)"


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    op = sys.argv[1]
    file_path = sys.argv[2]
    line = int(sys.argv[3]) - 1 if len(sys.argv) > 3 else 0  # Convert 1-based to 0-based
    char = int(sys.argv[4]) - 1 if len(sys.argv) > 4 else 0

    result = lsp_session(op, file_path, line, char)

    if op == "hover":
        print(format_hover(result))
    elif op == "definition":
        print(format_definition(result))
    elif op == "references":
        print(format_definition(result))  # Same format
    elif op == "symbols":
        print(format_symbols(result))
    elif op == "diagnostics":
        print(format_diagnostics(result))
    else:
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
