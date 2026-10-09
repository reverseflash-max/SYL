"""
SYL LAN sync: the PC is the hub, the phone syncs with it over Wi-Fi.

    python syl.py serve            (on the PC; prints the address and pairing code)

The app sends its whole library to POST /sync. The PC merges it with its own
library, saves the result and sends the merged library back; the app then
replaces its copy with that. Both sides end up with the same data.

Merge rules (nothing the user wrote is lost unless they deleted it):
  - Entities are matched by id. Name, type, book and chapter come from the copy
    edited most recently. Facts from both copies are kept, matched by fact id.
    Lore and Wikidata details are kept if only the older copy has them.
  - A deletion (data/deleted.json on either side) removes the entity, fact or
    link everywhere, unless the entity or link was edited or re-created after
    the deletion.
  - Links whose entities no longer exist are dropped.

Every request must carry the pairing code in the X-SYL-Code header.
"""

from __future__ import annotations

import copy
import json
import secrets
import shutil
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

import syl_core as core

DEFAULT_PORT = 8765
MAX_BODY = 50 * 1024 * 1024
BACKUP_DIR_NAME = "_sync_backup"


# --------------------------------------------------------------------------
# merging (pure functions: no file access)
# --------------------------------------------------------------------------

def merge_deleted(a: dict, b: dict) -> dict:
    out = core.normalize_deleted(a)
    for kind, items in core.normalize_deleted(b).items():
        for key, ts in items.items():
            if key not in out[kind] or ts > out[kind][key]:
                out[kind][key] = ts
    return out


def _updated(e: dict) -> str:
    return e["metadata"]["last_updated"]


def merge_entity_pair(a: dict, b: dict) -> dict:
    """Two copies of the same entity -> one, keeping every fact."""
    newer, older = (a, b) if _updated(a) >= _updated(b) else (b, a)
    out = copy.deepcopy(newer)
    facts = {f["id"]: f for f in older["user_captured_facts"]}
    facts.update({f["id"]: f for f in newer["user_captured_facts"]})
    out["user_captured_facts"] = core.dedupe_facts(facts.values())
    if older["ai_lore_enhancement"]["biography"] and not out["ai_lore_enhancement"]["biography"]:
        out["ai_lore_enhancement"] = copy.deepcopy(older["ai_lore_enhancement"])
    if older["external_data"]["wikidata_id"] and not out["external_data"]["wikidata_id"]:
        out["external_data"] = copy.deepcopy(older["external_data"])
    out["metadata"]["first_seen"] = min(a["metadata"]["first_seen"], b["metadata"]["first_seen"])
    return out


def merge_libraries(local: dict, remote: dict) -> dict:
    """
    local / remote: {"entities": [...], "relationships": [...], "deleted": {...}}
    Returns the merged library in the same shape. Inputs are not modified.
    """
    deleted = merge_deleted(local.get("deleted") or {}, remote.get("deleted") or {})

    entities: dict[str, dict] = {}
    for raw in list(local.get("entities") or []) + list(remote.get("entities") or []):
        e = core.normalize_entity(raw, raw.get("id"))
        try:
            core.entity_path(e["id"])
        except ValueError:
            continue
        entities[e["id"]] = merge_entity_pair(entities[e["id"]], e) if e["id"] in entities else e

    gone_facts = deleted["facts"]
    for eid in list(entities):
        e = entities[eid]
        when = deleted["entities"].get(eid)
        if when is not None and when >= _updated(e):
            del entities[eid]
            continue
        e["user_captured_facts"] = [f for f in e["user_captured_facts"] if f["id"] not in gone_facts]

    rels: dict[str, dict] = {}
    for raw in list(local.get("relationships") or []) + list(remote.get("relationships") or []):
        if not isinstance(raw, dict) or not raw.get("source") or not raw.get("target"):
            continue
        r = {
            "source": raw["source"],
            "target": raw["target"],
            "type": raw.get("type") or "Related to",
            "description": raw.get("description") or "",
            "chapter": core.parse_chapter(raw.get("chapter"), 0) or None,
            "created_at": core.normalize_timestamp(raw.get("created_at")),
        }
        key = core.relationship_key(r)
        if key not in rels or r["created_at"] > rels[key]["created_at"]:
            rels[key] = r
    kept_rels = []
    for key, r in rels.items():
        if r["source"] not in entities or r["target"] not in entities:
            continue
        when = deleted["relationships"].get(key)
        if when is not None and when >= r["created_at"]:
            continue
        kept_rels.append(r)
    kept_rels.sort(key=lambda r: (r["created_at"], core.relationship_key(r)))

    return {
        "entities": sorted(entities.values(), key=lambda e: e["name"].lower()),
        "relationships": kept_rels,
        "deleted": deleted,
    }


# --------------------------------------------------------------------------
# the PC's library on disk
# --------------------------------------------------------------------------

def load_library() -> dict:
    return {
        "entities": core.load_all_entities(),
        "relationships": core.load_relationships(),
        "deleted": core.load_deleted(),
    }


def backup_library() -> None:
    """Keep a copy of the library as it was before the last sync."""
    backup = core.DATA_DIR / BACKUP_DIR_NAME
    if backup.exists():
        shutil.rmtree(backup)
    backup.mkdir(parents=True)
    if core.ENTITIES_DIR.exists():
        shutil.copytree(core.ENTITIES_DIR, backup / "entities")
    for f in (core.RELATIONSHIPS_FILE, core.DELETED_FILE):
        if f.exists():
            shutil.copy2(f, backup / f.name)


def write_library(lib: dict) -> dict[str, int]:
    """Save a merged library, touching only files whose content changed."""
    current = {e["id"]: e for e in core.load_all_entities()}
    written = removed = 0
    for e in lib["entities"]:
        if current.pop(e["id"], None) != e:
            core._write_json(core.entity_path(e["id"]), e)  # keep its last_updated as is
            written += 1
    for eid in current:
        core.entity_path(eid).unlink(missing_ok=True)
        removed += 1
    core.save_relationships(lib["relationships"])
    core.save_deleted(lib["deleted"])
    return {"written": written, "removed": removed}


_lock = threading.Lock()


def sync_with(remote: dict) -> tuple[dict, dict[str, int]]:
    with _lock:
        local = load_library()
        merged = merge_libraries(local, remote)
        backup_library()
        stats = write_library(merged)
        return merged, stats


# --------------------------------------------------------------------------
# server
# --------------------------------------------------------------------------

def pairing_code() -> str:
    """The code the phone must send. Made once and kept in settings.json."""
    s = core.load_settings()
    if not s.get("sync_code"):
        s["sync_code"] = f"{secrets.randbelow(10**6):06d}"
        core.save_settings(s)
    return s["sync_code"]


def lan_address() -> str:
    """Best guess at this PC's Wi-Fi address (no traffic is sent)."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


class SyncHandler(BaseHTTPRequestHandler):
    server_version = "SYL"
    code = ""  # set by serve()

    def _send(self, status: int, body: Any) -> None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authorised(self) -> bool:
        given = self.headers.get("X-SYL-Code", "")
        if secrets.compare_digest(given.encode(), self.code.encode()):
            return True
        self._send(401, {"error": "Wrong pairing code. Run `python syl.py serve` on the PC to see it."})
        return False

    def do_GET(self):
        if self.path.rstrip("/") != "/ping":
            return self._send(404, {"error": "not found"})
        if not self._authorised():
            return
        self._send(200, {"app": "syl", "schema_version": core.SCHEMA_VERSION,
                         "entities": len(core.load_all_entities())})

    def do_POST(self):
        if self.path.rstrip("/") != "/sync":
            return self._send(404, {"error": "not found"})
        if not self._authorised():
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return self._send(413, {"error": "Request is empty or too large."})
        try:
            remote = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(remote, dict):
                raise ValueError("expected a JSON object")
            if int(remote.get("schema_version") or core.SCHEMA_VERSION) > core.SCHEMA_VERSION:
                return self._send(409, {"error": "The app is newer than the PC tools. Update SYL on the PC."})
        except (ValueError, UnicodeDecodeError) as e:
            return self._send(400, {"error": f"Bad request: {e}"})
        merged, stats = sync_with(remote)
        print(f"[{core.now_iso()}] Synced with {self.client_address[0]}: "
              f"{len(merged['entities'])} entries, {stats['written']} saved, {stats['removed']} removed")
        self._send(200, {"schema_version": core.SCHEMA_VERSION, **merged})

    def log_message(self, fmt, *args):  # quiet: sync_with prints a summary line
        pass


def serve(host: str = "0.0.0.0", port: int = DEFAULT_PORT) -> None:
    SyncHandler.code = pairing_code()
    httpd = ThreadingHTTPServer((host, port), SyncHandler)
    print("SYL sync server running. In the app (Reading tab, Sync with your PC) enter:")
    print(f"  Address:      http://{lan_address()}:{port}")
    print(f"  Pairing code: {SyncHandler.code}")
    print("Phone and PC must be on the same Wi-Fi. Allow Python through Windows Firewall if asked.")
    print("Press Ctrl+C to stop.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        httpd.server_close()
