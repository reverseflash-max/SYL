"""
SYL core: the one place that knows how SYL data is stored.

Every CLI command and the Flutter app use the same layout:

    data/
      entities/<id>.json     one file per entity (schema below)
      relationships.json     list of links between entity ids
      settings.json          reading progress, LM Studio and sync settings
      deleted.json           what was deleted and when, so a sync can't bring it back

Entity id rules: the Wikidata QID when there is one (Q180322), otherwise a
slug of the name (frodo-baggins). The id is also stored inside the file.

Entity schema (schema_version 2), all keys snake_case:

    {
      "schema_version": 2,
      "id": "Q180322",
      "name": "Aragorn",
      "type": "Character",            # Character | Location | Item | Lore | Other
      "book": "The Lord of the Rings", # or null
      "discovery_chapter": 1,          # int
      "user_captured_facts": [
        {"id": "f_ab12cd34", "text": "...", "chapter": 3,
         "timestamp": "2026-09-19T20:42:14", "source": "user"}
      ],
      "ai_lore_enhancement": {
        "description": "", "biography": "", "lore_tags": [],
        "generated_at": null, "model": null, "spoiler_limit_chapter": null
      },
      "external_data": {
        "wikidata_id": "Q180322", "description": "...",
        "aliases": [], "instance_of": []
      },
      "metadata": {
        "first_seen": "2026-09-19", "last_updated": "2026-09-23T10:00:00",
        "status": "active", "source": "wikidata"
      }
    }

deleted.json (tombstones; written by every delete, read by `syl.py serve`):

    {
      "entities":      {"frodo-baggins": "2026-10-09T12:00:00"},
      "facts":         {"f_ab12cd34": "2026-10-09T12:00:00"},
      "relationships": {"Q204274|Q180322|mentor": "2026-10-09T12:00:00"}
    }

A relationship's key is "source|target|type", with the type lowercased.
"""

from __future__ import annotations

import json
import os
import re
import unicodedata
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

SCHEMA_VERSION = 2
ENTITY_TYPES = ["Character", "Location", "Item", "Lore", "Other"]

PROJECT_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.environ.get("SYL_DATA_DIR", PROJECT_DIR / "data"))
ENTITIES_DIR = DATA_DIR / "entities"
RELATIONSHIPS_FILE = DATA_DIR / "relationships.json"
SETTINGS_FILE = DATA_DIR / "settings.json"
DELETED_FILE = DATA_DIR / "deleted.json"

DEFAULT_SETTINGS: dict[str, Any] = {
    "current_book": None,
    # Spoiler shield: nothing from a later chapter is shown or sent to the AI.
    # null means "no limit".
    "spoiler_chapter": None,
    "lm_studio_url": "http://127.0.0.1:1234",
    # Empty means "use whichever model LM Studio has loaded".
    "lm_model": "",
    # LAN sync (`syl.py serve` on the PC, "Sync with your PC" in the app).
    # sync_url is the PC's address as the phone sees it; sync_code is the
    # pairing code both sides must share.
    "sync_url": "",
    "sync_code": "",
}


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------

def now_iso() -> str:
    return datetime.now().replace(microsecond=0).isoformat()


def today() -> str:
    return datetime.now().strftime("%Y-%m-%d")


def slugify(name: str) -> str:
    text = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text).strip("-").lower()
    return text or "entity"


def is_qid(value: str | None) -> bool:
    return bool(value) and re.fullmatch(r"Q\d+", value.strip()) is not None


def parse_chapter(value: Any, default: int = 1) -> int:
    """'Chapter 3', '3', 3, None -> int."""
    if isinstance(value, bool):
        return default
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        m = re.search(r"\d+", value)
        if m:
            return int(m.group())
    return default


def normalize_type(value: Any) -> str:
    if not isinstance(value, str) or not value.strip():
        return "Other"
    v = value.strip().lower()
    for t in ENTITY_TYPES:
        if v == t.lower() or v == t.lower() + "s":
            return t
    if v in ("place", "places"):
        return "Location"
    return "Other"


def type_from_label(value: Any) -> str:
    """'Character' -> Character, 'Elf' -> Character, 'City' -> Location."""
    t = normalize_type(value)
    return guess_type([value]) if t == "Other" and isinstance(value, str) else t


def normalize_timestamp(value: Any) -> str:
    if isinstance(value, str) and value.strip():
        s = value.strip().replace(" ", "T", 1)
        try:
            return datetime.fromisoformat(s).replace(microsecond=0).isoformat()
        except ValueError:
            return s
    return now_iso()


def new_fact_id() -> str:
    return "f_" + uuid.uuid4().hex[:8]


TYPE_KEYWORDS = [
    ("Character", ["character", "human", "person", "elf", "dwarf", "hobbit", "wizard",
                   "deity", "god", "being", "creature", "orc", "dragon", "mistborn", "hero",
                   "king", "queen"]),
    ("Location", ["location", "locality", "city", "town", "village", "realm", "kingdom",
                  "country", "region", "place", "fortress", "castle", "forest", "mountain",
                  "river", "continent", "world", "planet", "capital", "island", "tower",
                  "sea", "lake", "valley", "land"]),
    ("Item", ["item", "object", "weapon", "sword", "artifact", "artefact", "ring", "jewel",
              "gem", "book", "armour", "armor", "staff", "ship", "vehicle"]),
    ("Lore", ["organization", "organisation", "group", "order", "language", "event",
              "war", "battle", "religion", "magic", "race", "species", "people"]),
]


def guess_type(instance_labels: list[str]) -> str:
    text = " ".join(instance_labels).lower()
    for type_, words in TYPE_KEYWORDS:
        for w in words:
            if f" {w}" in f" {text}":
                return type_
    return "Other"



# --------------------------------------------------------------------------
# entity construction / normalisation
# --------------------------------------------------------------------------

def empty_lore() -> dict[str, Any]:
    return {
        "description": "",
        "biography": "",
        "lore_tags": [],
        "generated_at": None,
        "model": None,
        "spoiler_limit_chapter": None,
    }


def new_entity(name: str, type_: str = "Other", *, entity_id: str | None = None,
               book: str | None = None, discovery_chapter: int = 1,
               source: str = "manual") -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "id": entity_id or slugify(name),
        "name": name.strip(),
        "type": normalize_type(type_),
        "book": book,
        "discovery_chapter": discovery_chapter,
        "user_captured_facts": [],
        "ai_lore_enhancement": empty_lore(),
        "external_data": {
            "wikidata_id": entity_id if is_qid(entity_id) else None,
            "description": "",
            "aliases": [],
            "instance_of": [],
        },
        "metadata": {
            "first_seen": today(),
            "last_updated": now_iso(),
            "status": "active",
            "source": source,
        },
    }


def _get(d: dict, *keys, default=None):
    """First present key, so old snake_case and camelCase files both load."""
    for k in keys:
        if isinstance(d, dict) and k in d and d[k] is not None:
            return d[k]
    return default


def normalize_fact(raw: dict) -> dict[str, Any] | None:
    text = str(_get(raw, "text", default="")).strip()
    if not text:
        return None
    return {
        "id": _get(raw, "id", default=None) or new_fact_id(),
        "text": text,
        "chapter": parse_chapter(_get(raw, "chapter"), 1),
        "timestamp": normalize_timestamp(_get(raw, "timestamp")),
        "source": _get(raw, "source", default="user"),
    }


def normalize_entity(raw: dict, fallback_id: str | None = None) -> dict[str, Any]:
    """Turn any historical SYL file (v1 snake_case, app camelCase) into v2."""
    name = str(_get(raw, "name", default=fallback_id or "Unnamed")).strip()
    ext_raw = _get(raw, "external_data", "externalData", default={}) or {}
    wikidata_id = _get(ext_raw, "wikidata_id", "wikidataId")
    if not is_qid(wikidata_id):
        wikidata_id = None
    entity_id = _get(raw, "id") or wikidata_id or (fallback_id if is_qid(fallback_id) else None) or slugify(name)
    if wikidata_id is None and is_qid(entity_id):
        wikidata_id = entity_id

    lore_raw = _get(raw, "ai_lore_enhancement", "aiLoreEnhancement", default={}) or {}
    tags = _get(lore_raw, "lore_tags", "loreTags", default=[]) or []
    lore = empty_lore()
    lore.update({
        "description": str(_get(lore_raw, "description", default="")),
        "biography": str(_get(lore_raw, "biography", default="")),
        "lore_tags": [str(t) for t in tags],
        "generated_at": _get(lore_raw, "generated_at"),
        "model": _get(lore_raw, "model"),
        "spoiler_limit_chapter": _get(lore_raw, "spoiler_limit_chapter"),
    })

    meta_raw = _get(raw, "metadata", default={}) or {}
    facts = []
    for f in _get(raw, "user_captured_facts", "userCapturedFacts", default=[]) or []:
        nf = normalize_fact(f) if isinstance(f, dict) else None
        if nf:
            facts.append(nf)

    return {
        "schema_version": SCHEMA_VERSION,
        "id": entity_id,
        "name": name,
        "type": normalize_type(_get(raw, "type")),
        "book": _get(raw, "book"),
        "discovery_chapter": parse_chapter(_get(raw, "discovery_chapter", "discoveryChapter"), 1),
        "user_captured_facts": dedupe_facts(facts),
        "ai_lore_enhancement": lore,
        "external_data": {
            "wikidata_id": wikidata_id,
            "description": str(_get(ext_raw, "description", default="")),
            "aliases": list(_get(ext_raw, "aliases", default=[]) or []),
            "instance_of": list(_get(ext_raw, "instance_of", default=[]) or []),
        },
        "metadata": {
            "first_seen": str(_get(meta_raw, "first_seen", "firstSeen", default=today()))[:10],
            "last_updated": normalize_timestamp(_get(meta_raw, "last_updated", "lastUpdated")),
            "status": str(_get(meta_raw, "status", default="active")).lower(),
            "source": str(_get(meta_raw, "source", default="manual")),
        },
    }


def dedupe_facts(facts: Iterable[dict]) -> list[dict]:
    """Drop exact repeats (same text + chapter), keep the earliest, sort by chapter."""
    seen: dict[tuple, dict] = {}
    for f in facts:
        key = (f["text"].strip().lower(), f["chapter"])
        if key not in seen or f["timestamp"] < seen[key]["timestamp"]:
            seen[key] = f
    return sorted(seen.values(), key=lambda f: (f["chapter"], f["timestamp"]))


def merge_entities(base: dict, other: dict) -> dict:
    """Merge `other` into `base` without losing anything the user wrote."""
    out = json.loads(json.dumps(base))
    out["user_captured_facts"] = dedupe_facts(base["user_captured_facts"] + other["user_captured_facts"])
    if out["type"] == "Other" and other["type"] != "Other":
        out["type"] = other["type"]
    out["book"] = out.get("book") or other.get("book")
    out["discovery_chapter"] = min(base["discovery_chapter"], other["discovery_chapter"])
    for k in ("description", "biography"):
        if not out["ai_lore_enhancement"][k] and other["ai_lore_enhancement"][k]:
            out["ai_lore_enhancement"][k] = other["ai_lore_enhancement"][k]
    ext, oext = out["external_data"], other["external_data"]
    ext["wikidata_id"] = ext["wikidata_id"] or oext["wikidata_id"]
    ext["description"] = ext["description"] or oext["description"]
    ext["aliases"] = sorted(set(ext["aliases"]) | set(oext["aliases"]))
    ext["instance_of"] = sorted(set(ext["instance_of"]) | set(oext["instance_of"]))
    out["metadata"]["first_seen"] = min(base["metadata"]["first_seen"], other["metadata"]["first_seen"])
    out["metadata"]["last_updated"] = now_iso()
    return out


# --------------------------------------------------------------------------
# storage
# --------------------------------------------------------------------------

def _write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)


def _read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def entity_path(entity_id: str) -> Path:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", entity_id):
        raise ValueError(f"Bad entity id: {entity_id!r}")
    return ENTITIES_DIR / f"{entity_id}.json"


def load_entity(entity_id: str) -> dict | None:
    try:
        path = entity_path(entity_id)
    except ValueError:
        return None
    raw = _read_json(path, None)
    return normalize_entity(raw, entity_id) if raw else None


def save_entity(entity: dict) -> Path:
    entity = normalize_entity(entity, entity.get("id"))
    entity["metadata"]["last_updated"] = now_iso()
    path = entity_path(entity["id"])
    _write_json(path, entity)
    return path


def delete_entity(entity_id: str) -> bool:
    path = entity_path(entity_id)
    if path.exists():
        path.unlink()
        record_deletion("entities", entity_id)
        return True
    return False


def load_all_entities() -> list[dict]:
    out = []
    if ENTITIES_DIR.exists():
        for p in sorted(ENTITIES_DIR.glob("*.json")):
            try:
                out.append(normalize_entity(_read_json(p, {}), p.stem))
            except Exception as e:  # keep going; one bad file should not hide the rest
                print(f"Warning: could not read {p.name}: {e}")
    return out


def find_entity(query: str) -> dict | None:
    """By id, exact name, or alias (case-insensitive)."""
    q = query.strip().lower()
    entities = load_all_entities()
    for e in entities:
        if e["id"].lower() == q:
            return e
    for e in entities:
        if e["name"].lower() == q:
            return e
    for e in entities:
        if q in (a.lower() for a in e["external_data"]["aliases"]):
            return e
    return None


def add_fact(entity: dict, text: str, chapter: int, source: str = "user") -> dict:
    fact = normalize_fact({"text": text, "chapter": chapter, "timestamp": now_iso(), "source": source})
    if fact is None:
        raise ValueError("Fact text is empty")
    entity["user_captured_facts"] = dedupe_facts(entity["user_captured_facts"] + [fact])
    return fact


# ---- relationships -------------------------------------------------------

def load_relationships() -> list[dict]:
    rels = _read_json(RELATIONSHIPS_FILE, [])
    out = []
    for r in rels:
        src, tgt = r.get("source"), r.get("target")
        if not src or not tgt:
            continue
        out.append({
            "source": src,
            "target": tgt,
            "type": r.get("type") or "Related to",
            "description": r.get("description") or "",
            "chapter": parse_chapter(r.get("chapter"), 0) or None,
            "created_at": normalize_timestamp(r.get("created_at")),
        })
    return out


def save_relationships(rels: list[dict]) -> None:
    _write_json(RELATIONSHIPS_FILE, rels)


def add_relationship(source_id: str, target_id: str, type_: str,
                     description: str = "", chapter: int | None = None) -> dict:
    rels = load_relationships()
    for r in rels:
        if r["source"] == source_id and r["target"] == target_id and r["type"].lower() == type_.lower():
            raise ValueError("That relationship already exists")
    rel = {"source": source_id, "target": target_id, "type": type_,
           "description": description, "chapter": chapter, "created_at": now_iso()}
    rels.append(rel)
    save_relationships(rels)
    return rel


def remove_relationship(source_id: str, target_id: str, type_: str | None = None) -> int:
    rels = load_relationships()
    keep = [r for r in rels if not (r["source"] == source_id and r["target"] == target_id
                                   and (type_ is None or r["type"].lower() == type_.lower()))]
    save_relationships(keep)
    for r in rels:
        if r not in keep:
            record_deletion("relationships", relationship_key(r))
    return len(rels) - len(keep)


def relationship_key(rel: dict) -> str:
    return f"{rel['source']}|{rel['target']}|{rel['type'].strip().lower()}"


# ---- deletions (tombstones) ------------------------------------------------

DELETED_KINDS = ("entities", "facts", "relationships")


def load_deleted() -> dict[str, dict[str, str]]:
    raw = _read_json(DELETED_FILE, {}) or {}
    return normalize_deleted(raw)


def normalize_deleted(raw: Any) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {k: {} for k in DELETED_KINDS}
    if isinstance(raw, dict):
        for kind in DELETED_KINDS:
            for key, ts in (raw.get(kind) or {}).items():
                out[kind][str(key)] = normalize_timestamp(ts)
    return out


def save_deleted(deleted: dict) -> None:
    _write_json(DELETED_FILE, normalize_deleted(deleted))


def record_deletion(kind: str, key: str) -> None:
    deleted = load_deleted()
    deleted[kind][key] = now_iso()
    save_deleted(deleted)


# ---- settings / spoiler shield -------------------------------------------

def load_settings() -> dict:
    s = dict(DEFAULT_SETTINGS)
    s.update(_read_json(SETTINGS_FILE, {}) or {})
    return s


def save_settings(settings: dict) -> None:
    merged = dict(DEFAULT_SETTINGS)
    merged.update(settings)
    _write_json(SETTINGS_FILE, merged)


def visible_facts(entity: dict, spoiler_chapter: int | None) -> list[dict]:
    """Facts at or before the spoiler chapter (all facts if no limit)."""
    facts = entity["user_captured_facts"]
    if spoiler_chapter is None:
        return list(facts)
    return [f for f in facts if f["chapter"] <= spoiler_chapter]


def mentions(entity: dict, entities: list[dict], spoiler_chapter: int | None = None) -> list[dict]:
    """Other entities whose name or alias appears in this entity's facts."""
    text = " ".join(f["text"] for f in visible_facts(entity, spoiler_chapter))
    found = []
    for other in entities:
        if other["id"] == entity["id"]:
            continue
        names = [other["name"], other["name"].split()[0]] + other["external_data"]["aliases"]
        for n in names:
            if len(n) >= 3 and re.search(r"\b" + re.escape(n) + r"\b", text, re.IGNORECASE):
                found.append(other)
                break
    return found
