#!/usr/bin/env python3
"""
One-time migration of SYL data to schema v2 (see syl_core.py).

- Reads every old data/*.json (CLI snake_case files and Flutter camelCase files)
- Merges duplicates of the same entity (same Wikidata id or same name)
- Drops exact duplicate facts and automated test notes
- Writes data/entities/<id>.json and rewrites data/relationships.json
- Moves the old files to data/_old_v1/ (nothing is deleted)

Safe to run twice: a second run finds nothing to migrate.
"""

import json
import shutil
import sys

import syl_core as core

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

SKIP = {"relationships.json", "settings.json"}
TEST_NOTE_MARKERS = ("test note", "automated test")
BOOK_HINTS = [("tolkien", "The Lord of the Rings"), ("middle-earth", "The Lord of the Rings"),
              ("mistborn", "Mistborn")]


def main():
    old_files = [p for p in sorted(core.DATA_DIR.glob("*.json")) if p.name not in SKIP]
    if not old_files:
        print("Nothing to migrate.")
        return

    merged: dict[str, dict] = {}
    alias_to_id: dict[str, str] = {}
    for p in old_files:
        raw = json.loads(p.read_text(encoding="utf-8"))
        e = core.normalize_entity(raw, p.stem)
        e["user_captured_facts"] = [f for f in e["user_captured_facts"]
                                    if not any(m in f["text"].lower() for m in TEST_NOTE_MARKERS)]
        # Old Wikidata fetches stored language codes as tags and a placeholder bio.
        lore = e["ai_lore_enhancement"]
        if all(len(t) <= 7 and t.islower() for t in lore["lore_tags"]) or \
                lore["biography"].startswith(("Source: Wikidata", "Generated lore based on", "Biography pending")):
            e["ai_lore_enhancement"] = core.empty_lore()
        if e["external_data"]["description"] == lore.get("description"):
            e["ai_lore_enhancement"]["description"] = ""
        # A few old entries pointed wikidata_id at 'N/A'.
        if not e.get("book"):
            d = e["external_data"]["description"].lower()
            for hint, book in BOOK_HINTS:
                if hint in d:
                    e["book"] = book
                    break

        key = e["external_data"]["wikidata_id"] or core.slugify(e["name"])
        existing_key = alias_to_id.get(e["name"].lower())
        if existing_key and existing_key != key:
            # same name, one copy has a QID and one doesn't: fold into the QID one
            if core.is_qid(key):
                merged[key] = core.merge_entities(e, merged.pop(existing_key))
            else:
                merged[existing_key] = core.merge_entities(merged[existing_key], e)
                key = existing_key
        elif key in merged:
            merged[key] = core.merge_entities(merged[key], e)
        else:
            merged[key] = e
        merged[key]["id"] = key
        alias_to_id[e["name"].lower()] = key
        alias_to_id[p.stem.lower()] = key

    # Books for entries that only had a sibling with a description.
    for e in merged.values():
        if not e.get("book"):
            d = e["external_data"]["description"].lower()
            for hint, book in BOOK_HINTS:
                if hint in d:
                    e["book"] = book

    core.ENTITIES_DIR.mkdir(parents=True, exist_ok=True)
    for e in merged.values():
        core.save_entity(e)
        print(f"  {e['id']:<16} {e['name']:<16} {e['type']:<10} {len(e['user_captured_facts'])} facts  book={e.get('book')}")

    # Relationships may refer to old file names; point them at the new ids.
    rels = core.load_relationships()
    for r in rels:
        r["source"] = alias_to_id.get(r["source"].lower(), r["source"])
        r["target"] = alias_to_id.get(r["target"].lower(), r["target"])
    core.save_relationships(rels)

    backup = core.DATA_DIR / "_old_v1"
    backup.mkdir(exist_ok=True)
    for p in old_files:
        shutil.move(str(p), str(backup / p.name))
    if not core.SETTINGS_FILE.exists():
        core.save_settings(core.DEFAULT_SETTINGS)
    print(f"Migrated {len(old_files)} old files into {len(merged)} entities. Originals are in data/_old_v1/.")


if __name__ == "__main__":
    main()
