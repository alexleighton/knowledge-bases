#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# ///
"""Find unused exported values in OCaml source files using ocaml-lsp.

Spawns ocamllsp, queries documentSymbol for each .mli file to find
exported val declarations, then checks textDocument/references for
each one.  Values with zero references outside their own module are
reported.

Only `val` declarations (LSP SymbolKind 13) are checked.  Types,
modules, and constructors are skipped — the reference index cannot
reliably track usage through record field access, qualified module
paths, or constructor pattern matching.  If a type is truly dead,
the values that construct and consume it will also be dead.

Prerequisites:
    dune build @ocaml-index

Usage:
    ./scripts/find-unused.py                  # scan all lib/ and bin/
    ./scripts/find-unused.py lib/data/char.ml # scan a single file
    ./scripts/find-unused.py -v               # verbose logging

Suppression:
    Add (* @unused-ok *) on the definition line in the .ml file
    to suppress a false positive (e.g. values consumed via functor).

Output format (tab-separated):
    file	line	symbol_name
"""

import argparse
import json
import os
import re
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path

VERBOSE = False

# ---------------------------------------------------------------------------
# Ignore list
# ---------------------------------------------------------------------------
# Symbol names to skip unconditionally.  These are known to be used
# via mechanisms invisible to the reference index:
#
#   pp, show  — generated or consumed by ppx_deriving.show at compile
#               time.  The index cannot track ppx-generated references.
IGNORED_NAMES = {"pp", "show"}

# LSP SymbolKind for val declarations (let-bindings / values).
SK_VALUE = 13


def log(msg):
    if VERBOSE:
        print(msg, file=sys.stderr)


# ---------------------------------------------------------------------------
# LSP JSON-RPC transport
# ---------------------------------------------------------------------------

# Per-request timeout (seconds).
RECV_TIMEOUT = 30

# Internal read buffer — bypasses Python's BufferedReader so that
# select(2) accurately reflects available data.
_lsp_buf = bytearray()


def _wait_ready(fd, deadline):
    """Block until *fd* is readable or *deadline* (monotonic) passes."""
    remaining = deadline - time.monotonic()
    if remaining <= 0 or not select.select([fd], [], [], max(0, remaining))[0]:
        raise TimeoutError(
            f"LSP server did not respond within {RECV_TIMEOUT}s")


def _read_line(fd, deadline):
    """Read one line (including newline) from *fd*."""
    while b"\n" not in _lsp_buf:
        _wait_ready(fd, deadline)
        chunk = os.read(fd, 8192)
        if not chunk:
            raise EOFError("LSP server closed stdout")
        _lsp_buf.extend(chunk)
    idx = _lsp_buf.index(b"\n")
    line = bytes(_lsp_buf[:idx + 1])
    del _lsp_buf[:idx + 1]
    return line


def _read_exact(fd, n, deadline):
    """Read exactly *n* bytes from *fd*."""
    while len(_lsp_buf) < n:
        _wait_ready(fd, deadline)
        chunk = os.read(fd, max(8192, n - len(_lsp_buf)))
        if not chunk:
            raise EOFError("LSP server closed stdout")
        _lsp_buf.extend(chunk)
    data = bytes(_lsp_buf[:n])
    del _lsp_buf[:n]
    return data


def send(proc, method, params, msg_id=None):
    """Send a JSON-RPC message to the LSP server."""
    msg = {"jsonrpc": "2.0", "method": method, "params": params}
    if msg_id is not None:
        msg["id"] = msg_id
    body = json.dumps(msg).encode("utf-8")
    header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
    log(f"  -> {method}" + (f" (id={msg_id})" if msg_id is not None else ""))
    proc.stdin.write(header + body)
    proc.stdin.flush()


def recv(proc, expected_id):
    """Read JSON-RPC messages until we get the response matching expected_id.

    Server-initiated notifications (no 'id') and responses to other
    requests are silently skipped.  Raises TimeoutError if no matching
    response arrives within RECV_TIMEOUT seconds.
    """
    fd = proc.stdout.fileno()
    deadline = time.monotonic() + RECV_TIMEOUT
    while True:
        headers = {}
        while True:
            line = _read_line(fd, deadline).decode("ascii").strip()
            if not line:
                break
            k, v = line.split(": ", 1)
            headers[k] = v
        length = int(headers["Content-Length"])
        body = _read_exact(fd, length, deadline)
        msg = json.loads(body)
        msg_id = msg.get("id")
        if msg_id == expected_id:
            log(f"  <- response id={msg_id}")
            return msg
        method = msg.get("method", "???")
        log(f"  <- skip: {method} (id={msg_id})")


def request(proc, msg_id, method, params):
    """Send a request and return the result (or None on error)."""
    send(proc, method, params, msg_id=msg_id)
    resp = recv(proc, msg_id)
    if "error" in resp:
        log(f"  LSP error ({method}): {resp['error']}")
        return None
    return resp.get("result")


def notify(proc, method, params):
    """Send a notification (no response expected)."""
    send(proc, method, params)


# ---------------------------------------------------------------------------
# LSP lifecycle
# ---------------------------------------------------------------------------

def start_server(root_uri, root_dir):
    """Spawn ocamllsp and perform the initialization handshake."""
    log(f"Starting ocamllsp (root={root_uri})")
    proc = subprocess.Popen(
        ["ocamllsp", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=root_dir,
    )
    result = request(proc, 0, "initialize", {
        "processId": os.getpid(),
        "rootUri": root_uri,
        "capabilities": {},
    })
    name = result.get("serverInfo", {}).get("name", "?")
    version = result.get("serverInfo", {}).get("version", "?")
    log(f"Server initialized: {name} {version}")
    notify(proc, "initialized", {})
    return proc


def stop_server(proc):
    """Shut down the LSP server."""
    log("Shutting down server")
    try:
        proc.stdin.close()
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    log("Server stopped")


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def find_ml_files(root, target_files):
    """Find .ml files to scan.

    If target_files is non-empty, resolve those paths relative to root.
    Otherwise, find all .ml files under lib/ and bin/.
    """
    if target_files:
        files = []
        for f in target_files:
            p = root / f
            if not p.exists():
                print(f"Warning: {f} does not exist, skipping",
                      file=sys.stderr)
                continue
            files.append(p)
        return files
    files = []
    for subdir in ["lib", "bin"]:
        d = root / subdir
        if d.is_dir():
            files.extend(sorted(d.glob("**/*.ml")))
    return files


# ---------------------------------------------------------------------------
# Symbol extraction
# ---------------------------------------------------------------------------

def exported_values(result):
    """Extract exported val declarations from a documentSymbol response.

    Only symbols with SymbolKind 13 (Value) are returned.  Types
    (kind 26), modules (kind 2), and constructors/fields (kind 22)
    are skipped — the reference index cannot reliably track their
    usage.

    Symbols with a ``containerName`` are also skipped — these are
    nested inside a module type or sub-module (e.g. ``val`` inside
    ``module type S = sig … end``) and are not real top-level
    exports of the compilation unit.
    """
    if not result:
        return []
    values = []
    for sym in result:
        if sym.get("kind") != SK_VALUE:
            continue
        if sym.get("containerName"):
            log(f"  {sym['name']}: inside {sym['containerName']}, skipping")
            continue
        if "location" in sym:
            start = sym["location"]["range"]["start"]
        elif "selectionRange" in sym:
            start = sym["selectionRange"]["start"]
        else:
            continue
        values.append({
            "name": sym["name"],
            "line": start["line"],
            "character": start["character"],
        })
    return values


def find_symbol_in_ml(ml_lines, name):
    """Find the definition of a symbol name in .ml source lines.

    Searches for 'let <name>' patterns.  Returns (line, character)
    or None.
    """
    pattern = re.compile(
        r'\b(let|type|module|exception)\s+' + re.escape(name) + r'\b')
    for i, line in enumerate(ml_lines):
        m = pattern.search(line)
        if m:
            col = m.start() + len(m.group(1)) + 1
            actual_col = line.find(name, col)
            if actual_col >= 0:
                return i, actual_col
    # Fallback: find any occurrence of the name
    for i, line in enumerate(ml_lines):
        col = line.find(name)
        if col >= 0:
            return i, col
    return None


# ---------------------------------------------------------------------------
# Reference checking
# ---------------------------------------------------------------------------

def open_file(proc, path, language_id="ocaml"):
    """Open a file in the LSP server."""
    uri = path.as_uri()
    text = path.read_text()
    notify(proc, "textDocument/didOpen", {
        "textDocument": {
            "uri": uri,
            "languageId": language_id,
            "version": 1,
            "text": text,
        },
    })
    return uri, text


def close_file(proc, uri):
    """Close a file in the LSP server."""
    notify(proc, "textDocument/didClose", {
        "textDocument": {"uri": uri},
    })


def find_unused(proc, root, target_files):
    """Scan .ml files and return unused exported values.

    Only files with a .mli are checked — the .mli defines the exported
    API surface.  Only val declarations (kind 13) are checked — types
    and modules are skipped because the index can't track usage through
    constructors, record fields, or qualified paths.

    References are queried from the .ml file, since the project-wide
    index works best from implementation files.
    """
    files = find_ml_files(root, target_files)
    print(f"Scanning {len(files)} file(s)...", file=sys.stderr)
    unused = []
    msg_id = 1

    for ml_path in files:
        rel = ml_path.relative_to(root)
        mli_path = ml_path.with_suffix(".mli")
        if not mli_path.exists():
            log(f"\n--- {rel} (no .mli, skipping) ---")
            continue
        log(f"\n--- {rel} ---")

        # Open the .ml file (needed for reference queries)
        ml_uri, ml_text = open_file(proc, ml_path)
        ml_lines = ml_text.splitlines()

        # Get exported val declarations from the .mli
        mli_uri, _ = open_file(proc, mli_path, "ocaml.interface")
        msg_id += 1
        result = request(proc, msg_id, "textDocument/documentSymbol", {
            "textDocument": {"uri": mli_uri},
        })
        close_file(proc, mli_uri)

        values = exported_values(result)
        log(f"  {len(values)} exported value(s)")

        # URIs to exclude from reference counts
        self_uris = {ml_uri, mli_path.as_uri()}

        for val in values:
            name = val["name"]

            if name in IGNORED_NAMES:
                log(f"  {name}: ignored")
                continue

            # Find the value's definition position in the .ml file
            pos = find_symbol_in_ml(ml_lines, name)
            if pos is None:
                log(f"  {name}: not found in .ml, skipping")
                continue
            line, char = pos
            msg_id += 1
            log(f"  {name} @ {line + 1}:{char}")
            refs = request(proc, msg_id, "textDocument/references", {
                "textDocument": {"uri": ml_uri},
                "position": {"line": line, "character": char},
                "context": {"includeDeclaration": True},
            })
            external = [
                r for r in (refs or [])
                if r.get("uri") not in self_uris
            ]
            log(f"    {len(refs or [])} total, {len(external)} external")

            if not external:
                # Allow suppression via (* @unused-ok *) comment on the
                # definition line — useful for values consumed through
                # functor application, which the reference index cannot
                # trace.
                if "@unused-ok" in ml_lines[line]:
                    log(f"    suppressed via @unused-ok")
                    continue
                unused.append({
                    "file": str(rel),
                    "line": line + 1,
                    "name": name,
                })

        close_file(proc, ml_uri)

    return unused


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    global VERBOSE
    parser = argparse.ArgumentParser(
        description="Find unused exported values in OCaml source files.")
    parser.add_argument(
        "files", nargs="*",
        help="Specific .ml files to scan (relative to project root). "
             "If omitted, scans all lib/ and bin/ files.")
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Enable verbose LSP protocol logging on stderr.")
    args = parser.parse_args()
    VERBOSE = args.verbose

    if not shutil.which("ocamllsp"):
        print("Error: ocamllsp not found in PATH", file=sys.stderr)
        sys.exit(1)

    root = Path(__file__).resolve().parent.parent
    # When run via dune, __file__ is inside _build/default/; use the source root.
    root_str = str(root)
    build_marker = os.sep + "_build" + os.sep
    if build_marker in root_str:
        root = Path(root_str[:root_str.index(build_marker)])
    root_uri = root.as_uri()

    proc = start_server(root_uri, root)
    try:
        results = find_unused(proc, root, args.files)
    finally:
        stop_server(proc)

    results.sort(key=lambda r: (r["file"], r["line"]))
    if results:
        print(f"Error: {len(results)} unused exported value(s):",
              file=sys.stderr)
        for r in results:
            print(f"  {r['file']}:{r['line']}\t{r['name']}")
        sys.exit(1)


if __name__ == "__main__":
    main()
