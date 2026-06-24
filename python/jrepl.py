#!/usr/bin/env python3
"""jrepl — a tiny stdin/stdout bridge to a Jupyter (ipykernel) kernel.

Run by the *active venv's* python from Neovim (see <leader>r in init.lua). It
starts one long-lived IPython kernel — so state (variables, imports) persists
across sends, giving a real "dynamic REPL" — and speaks a line-delimited JSON
protocol over stdio so the Lua side stays dependency-free.

Protocol
  in  (one JSON object per line on stdin):
        {"id": <int>, "code": "<source>"}
        {"id": <int>, "restart": true}        # restart the kernel, fresh state
  out (one JSON object per line on stdout):
        {"type": "ready"}                       # kernel is up, send away
        {"id": <int>, "type": "stream", "text": "..."}   # stdout/stderr
        {"id": <int>, "type": "result", "text": "..."}   # Out[n] / display
        {"id": <int>, "type": "error",  "text": "..."}   # traceback (no ANSI)
        {"id": <int>, "type": "done"}                    # execution finished
        {"type": "fatal", "text": "..."}        # startup/protocol failure

Only the kernel side needs ipykernel + jupyter_client (ipykernel depends on
jupyter_client, so one is enough). Neovim never imports them.
"""
import json
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def start_kernel():
    # Pin the kernel to THIS interpreter (the venv python that launched us),
    # not whatever the default 'python3' kernelspec points at.
    from jupyter_client import KernelManager

    km = KernelManager()
    km.kernel_cmd = [sys.executable, "-m", "ipykernel_launcher", "-f", "{connection_file}"]
    # silence client-side "kernel_cmd is deprecated" noise; it's the reliable way
    km.start_kernel()
    kc = km.client()
    kc.start_channels()
    kc.wait_for_ready(timeout=30)  # raises on a kernel that never comes up
    return km, kc


def run(kc, req_id, code):
    msg_id = kc.execute(code, allow_stdin=False)
    while True:
        try:
            msg = kc.get_iopub_msg(timeout=0.1)
        except Exception:
            # no message yet; keep waiting (execution may still be running)
            continue
        if msg.get("parent_header", {}).get("msg_id") != msg_id:
            continue
        t = msg["msg_type"]
        c = msg["content"]
        if t == "stream":
            emit({"id": req_id, "type": "stream", "text": c.get("text", "")})
        elif t in ("execute_result", "display_data"):
            text = (c.get("data", {}) or {}).get("text/plain", "")
            if text:
                emit({"id": req_id, "type": "result", "text": text})
        elif t == "error":
            tb = ANSI.sub("", "\n".join(c.get("traceback", [])))
            emit({"id": req_id, "type": "error", "text": tb})
        elif t == "status" and c.get("execution_state") == "idle":
            break
    emit({"id": req_id, "type": "done"})


def main():
    try:
        km, kc = start_kernel()
    except Exception as e:  # noqa: BLE001 — report any startup failure to nvim
        emit({"type": "fatal", "text": "kernel start failed: %r" % (e,)})
        return
    emit({"type": "ready"})
    # readline (not `for line in sys.stdin`) — the iterator read-ahead can hold a
    # line back on a pipe, stalling the first request indefinitely.
    for line in iter(sys.stdin.readline, ""):
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        if req.get("restart"):
            try:
                km.restart_kernel(now=True)
                kc.wait_for_ready(timeout=60)
                emit({"id": req.get("id", 0), "type": "done"})
            except Exception as e:  # noqa: BLE001
                emit({"type": "fatal", "text": "restart failed: %r" % (e,)})
            continue
        try:
            run(kc, req.get("id", 0), req.get("code", ""))
        except Exception as e:  # noqa: BLE001
            emit({"id": req.get("id", 0), "type": "error", "text": "jrepl: %r" % (e,)})
            emit({"id": req.get("id", 0), "type": "done"})


if __name__ == "__main__":
    main()
