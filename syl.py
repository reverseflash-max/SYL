#!/usr/bin/env python3
"""
SYL command line. One tool for everything the old scripts did.

    python syl.py list [--type Character] [--book "..."]
    python syl.py show Aragorn
    python syl.py search ring
    python syl.py stats

    python syl.py new "Samwise Gamgee" --type Character --book "The Lord of the Rings" --chapter 2
    python syl.py fact Aragorn 7 "He drew his sword"           (quick entry)
    python syl.py fetch "Frodo Baggins"                          (Wikidata: create or enrich)
    python syl.py import notes.txt                               (bulk import, text or JSON)

    python syl.py link Galadriel Aragorn Mentor --desc "She guides him" --chapter 3
    python syl.py unlink Galadriel Aragorn
    python syl.py links [Galadriel]
    python syl.py mentions Galadriel                             (names found inside facts)
    python syl.py resolve "Galadriel gave Frodo a phial"         (adds [[links]])

    python syl.py lore Aragorn          (AI biography from your facts via LM Studio)
    python syl.py lore --all
    python syl.py ai-check

    python syl.py settings --book "The Lord of the Rings" --chapter 7
    python syl.py settings --lm-url http://127.0.0.1:1234 --model qwen
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import syl_core as core

try:  # Windows consoles default to cp1252; SYL data has accents.
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass


def die(msg: str, code: int = 1):
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(code)


def require(query: str) -> dict:
    e = core.find_entity(query)
    if not e:
        die(f"No entity called '{query}'. Try: python syl.py list")
    return e


def spoiler_cap(args) -> int | None:
    if getattr(args, "all_chapters", False):
        return None
    if getattr(args, "chapter_cap", None) is not None:
        return args.chapter_cap
    return core.load_settings().get("spoiler_chapter")


# --------------------------------------------------------------------------
# browsing
# --------------------------------------------------------------------------

def cmd_list(args):
    ents = core.load_all_entities()
    if args.type:
        ents = [e for e in ents if e["type"].lower() == core.normalize_type(args.type).lower()]
    if args.book:
        ents = [e for e in ents if (e.get("book") or "").lower() == args.book.lower()]
    if not ents:
        print("No entities yet. Add one with: python syl.py new \"Name\"")
        return
    cap = spoiler_cap(args)
    print(f"{'ID':<16} {'Name':<22} {'Type':<10} {'Facts':>5}  Book")
    print("-" * 78)
    for e in sorted(ents, key=lambda e: e["name"].lower()):
        n = len(core.visible_facts(e, cap))
        print(f"{e['id']:<16} {e['name'][:22]:<22} {e['type']:<10} {n:>5}  {e.get('book') or '-'}")
    if cap is not None:
        print(f"\n(Spoiler shield: showing facts up to chapter {cap})")


def cmd_show(args):
    e = require(args.entity)
    cap = spoiler_cap(args)
    ext, lore = e["external_data"], e["ai_lore_enhancement"]
    print(f"{e['name']}  [{e['type']}]  id={e['id']}")
    if e.get("book"):
        print(f"Book: {e['book']}  |  first seen: chapter {e['discovery_chapter']}")
    if ext["wikidata_id"]:
        print(f"Wikidata: {ext['wikidata_id']}  {ext['description']}")
    if ext["aliases"]:
        print(f"Also known as: {', '.join(ext['aliases'])}")
    print()
    if lore["biography"]:
        print("Lore:")
        print(f"  {lore['description']}")
        print(f"  {lore['biography']}")
        if lore["lore_tags"]:
            print(f"  Tags: {', '.join(lore['lore_tags'])}")
        print(f"  (written by {lore['model']} from facts up to ch {lore['spoiler_limit_chapter']})")
        print()
    facts = core.visible_facts(e, cap)
    hidden = len(e["user_captured_facts"]) - len(facts)
    print(f"Facts ({len(facts)}):")
    for f in facts:
        print(f"  Ch {f['chapter']:>3}  {f['text']}")
    if hidden:
        print(f"  ...{hidden} more hidden by the spoiler shield (chapter {cap}). Use --all-chapters to see them.")
    ents = {x["id"]: x for x in core.load_all_entities()}
    rels = [r for r in core.load_relationships() if e["id"] in (r["source"], r["target"])]
    if rels:
        print("\nConnections:")
        for r in rels:
            if r["source"] == e["id"]:
                print(f"  {r['type']} -> {ents.get(r['target'], {}).get('name', r['target'])}")
            else:
                print(f"  {ents.get(r['source'], {}).get('name', r['source'])} is {r['type']} of {e['name']}")
    m = core.mentions(e, list(ents.values()), cap)
    if m:
        print(f"\nMentioned in facts: {', '.join(x['name'] for x in m)}")


def cmd_search(args):
    q = args.query.lower()
    cap = spoiler_cap(args)
    hits = []
    for e in core.load_all_entities():
        where = []
        if q in e["name"].lower() or any(q in a.lower() for a in e["external_data"]["aliases"]):
            where.append("name")
        if q in e["external_data"]["description"].lower():
            where.append("wikidata")
        for f in core.visible_facts(e, cap):
            if q in f["text"].lower():
                where.append(f"ch {f['chapter']}: {f['text']}")
        if q in " ".join(e["ai_lore_enhancement"]["lore_tags"]).lower():
            where.append("tag")
        if where:
            hits.append((e, where))
    if not hits:
        print(f"Nothing matches '{args.query}'.")
    for e, where in hits:
        print(f"{e['name']} ({e['type']})")
        for w in where:
            print(f"    {w}")


def cmd_stats(args):
    ents = core.load_all_entities()
    facts = [f for e in ents for f in e["user_captured_facts"]]
    by_type = {}
    for e in ents:
        by_type[e["type"]] = by_type.get(e["type"], 0) + 1
    s = core.load_settings()
    print(f"Entities: {len(ents)}   Facts: {len(facts)}   Links: {len(core.load_relationships())}")
    print("By type: " + ", ".join(f"{k} {v}" for k, v in sorted(by_type.items())))
    print(f"With AI lore: {sum(1 for e in ents if e['ai_lore_enhancement']['biography'])}")
    print(f"Linked to Wikidata: {sum(1 for e in ents if e['external_data']['wikidata_id'])}")
    if facts:
        print(f"Chapters covered: {len({f['chapter'] for f in facts})} (up to {max(f['chapter'] for f in facts)})")
    print(f"Reading: {s.get('current_book') or '-'}   Spoiler shield: "
          f"{'chapter ' + str(s['spoiler_chapter']) if s.get('spoiler_chapter') else 'off'}")


# --------------------------------------------------------------------------
# adding things
# --------------------------------------------------------------------------

def cmd_new(args):
    if core.find_entity(args.name):
        die(f"'{args.name}' already exists.")
    book = args.book or core.load_settings().get("current_book")
    e = core.new_entity(args.name, args.type, book=book, discovery_chapter=args.chapter)
    if core.entity_path(e["id"]).exists():
        die(f"An entity with id {e['id']} already exists.")
    core.save_entity(e)
    print(f"Created {e['name']} ({e['type']}) as {e['id']}.")
    if args.wikidata:
        args.query, args.pick, args.yes = args.name, None, False
        cmd_fetch(args)


def cmd_fact(args):
    e = core.find_entity(args.entity)
    if not e:
        if not args.create:
            die(f"No entity called '{args.entity}'. Add --create to make it.")
        e = core.new_entity(args.entity, args.type or "Other",
                            book=core.load_settings().get("current_book"), discovery_chapter=args.chapter)
    core.add_fact(e, args.text, args.chapter)
    if args.chapter < e["discovery_chapter"]:
        e["discovery_chapter"] = args.chapter
    core.save_entity(e)
    print(f"Added to {e['name']} (ch {args.chapter}): {args.text}")


def cmd_fetch(args):
    import syl_wikidata as wd
    query = args.query.strip()
    try:
        if core.is_qid(query):
            chosen = query.upper()
        else:
            existing = core.find_entity(query)
            hint = args.book or (existing or {}).get("book") or core.load_settings().get("current_book")
            results = wd.search(query, hint=hint)
            if not results:
                die(f"Wikidata has nothing for '{query}'.")
            if args.pick:
                if not 1 <= args.pick <= len(results):
                    die(f"--pick must be between 1 and {len(results)}")
                chosen = results[args.pick - 1]["id"]
            elif len(results) == 1 or args.yes or not sys.stdin.isatty():
                chosen = results[0]["id"]
                print(f"Using {results[0]['label']} ({chosen}): {results[0]['description']}")
                if len(results) > 1:
                    print("  (not right? rerun with --pick N; see: python syl.py fetch \"...\" in a terminal)")
            else:
                for i, r in enumerate(results, 1):
                    print(f"  {i}. {r['label']} ({r['id']}) - {r['description'] or 'no description'}")
                ans = input("Which one? [1] ").strip() or "1"
                if not ans.isdigit() or not 1 <= int(ans) <= len(results):
                    die("Cancelled.")
                chosen = results[int(ans) - 1]["id"]
        info = wd.fetch(chosen)
    except wd.WikidataError as e:
        die(str(e))

    # Find the entity this belongs to: same QID, same name, or an alias.
    target = None
    for e in core.load_all_entities():
        if e["external_data"]["wikidata_id"] == info["id"] or e["id"] == info["id"]:
            target = e
            break
    target = target or core.find_entity(query if not core.is_qid(query) else info["label"])
    created = target is None
    if created:
        target = core.new_entity(info["label"], "Other", entity_id=info["id"],
                                 book=args.book or core.load_settings().get("current_book"),
                                 source="wikidata")
    wd.apply_to_entity(target, info)
    if args.book and not target.get("book"):
        target["book"] = args.book
    core.save_entity(target)
    verb = "Created" if created else "Updated"
    print(f"{verb} {target['name']} ({target['type']}, {info['id']}): {info['description']}")
    if info["instance_of"]:
        print(f"  Wikidata says: {', '.join(info['instance_of'])}")
    if not created:
        print(f"  Your {len(target['user_captured_facts'])} facts were kept.")


def _parse_text_import(content: str) -> list[dict]:
    """
    Name: Type            (Type optional: "Name:" alone is fine)
    Chapter 5: a fact
    5: a fact
    ---
    """
    items, cur = [], None
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line == "---":
            cur = None
            continue
        fm = re.match(r"^(?:ch(?:apter)?\.?\s*)?(\d+)\s*:\s*(.+)$", line, re.IGNORECASE)
        if fm and cur is not None:
            cur["facts"].append({"chapter": int(fm.group(1)), "text": fm.group(2).strip()})
            continue
        hm = re.match(r"^(.+?)\s*:\s*(.*)$", line)
        if hm and not fm:
            cur = {"name": hm.group(1).strip(), "type": hm.group(2).strip() or "Other", "facts": []}
            items.append(cur)
            continue
        print(f"  Skipped line: {line}")
    return items


def cmd_import(args):
    path = Path(args.file)
    if not path.exists():
        die(f"{path} not found")
    content = path.read_text(encoding="utf-8")
    try:
        data = json.loads(content)
        items = data if isinstance(data, list) else [data]
    except json.JSONDecodeError:
        items = _parse_text_import(content)
    book = args.book or core.load_settings().get("current_book")
    created = updated = added = 0
    for it in items:
        name = str(it.get("name", "")).strip()
        if not name:
            continue
        e = core.find_entity(name)
        if e is None:
            facts = it.get("facts", [])
            first = min((core.parse_chapter(f.get("chapter")) for f in facts), default=1)
            e = core.new_entity(name, core.type_from_label(it.get("type")), book=it.get("book") or book,
                                discovery_chapter=first, source="bulk_import")
            created += 1
        else:
            updated += 1
            if e["type"] == "Other":
                e["type"] = core.type_from_label(it.get("type"))
        before = len(e["user_captured_facts"])
        for f in it.get("facts", []):
            core.add_fact(e, f.get("text", ""), core.parse_chapter(f.get("chapter")))
        added += len(e["user_captured_facts"]) - before
        core.save_entity(e)
    print(f"Imported: {created} new, {updated} updated, {added} facts added (duplicates skipped).")


# --------------------------------------------------------------------------
# links
# --------------------------------------------------------------------------

def cmd_link(args):
    s, t = require(args.source), require(args.target)
    try:
        core.add_relationship(s["id"], t["id"], args.type, args.desc or "", args.chapter)
    except ValueError as e:
        die(str(e))
    print(f"Linked: {s['name']} -> {args.type} -> {t['name']}")


def cmd_unlink(args):
    s, t = require(args.source), require(args.target)
    n = core.remove_relationship(s["id"], t["id"], args.type)
    print(f"Removed {n} link(s)." if n else "No matching link.")


def cmd_links(args):
    ents = {e["id"]: e for e in core.load_all_entities()}
    rels = core.load_relationships()
    if args.entity:
        eid = require(args.entity)["id"]
        rels = [r for r in rels if eid in (r["source"], r["target"])]
    if not rels:
        print("No links yet.")
    for r in rels:
        sn = ents.get(r["source"], {}).get("name", r["source"])
        tn = ents.get(r["target"], {}).get("name", r["target"])
        ch = f" (ch {r['chapter']})" if r.get("chapter") else ""
        print(f"{sn} -> {r['type']} -> {tn}{ch}")
        if r["description"]:
            print(f"    {r['description']}")


def cmd_mentions(args):
    e = require(args.entity)
    found = core.mentions(e, core.load_all_entities(), spoiler_cap(args))
    print(", ".join(x["name"] for x in found) if found else "No other entities are named in its facts.")


def cmd_resolve(args):
    text = args.text
    ents = sorted(core.load_all_entities(), key=lambda e: -len(e["name"]))
    for e in ents:
        for n in [e["name"]] + e["external_data"]["aliases"] + [e["name"].split()[0]]:
            if len(n) < 3:
                continue
            pat = r"(?<!\[\[)\b" + re.escape(n) + r"\b(?![^\[]*\]\])"
            if re.search(pat, text, re.IGNORECASE):
                text = re.sub(pat, lambda m: f"[[{e['id']}|{m.group(0)}]]", text, count=1, flags=re.IGNORECASE)
                break
    print(text)


# --------------------------------------------------------------------------
# AI
# --------------------------------------------------------------------------

def cmd_ai_check(args):
    import syl_ai as ai
    s = core.load_settings()
    url = s["lm_studio_url"]
    try:
        models = ai.list_models(url)
    except ai.AIError as e:
        die(str(e))
    print(f"LM Studio OK at {url}")
    for m in models:
        print(f"  - {m}")
    print(f"SYL will use: {ai.pick_model(url, s.get('lm_model', ''))}")


def cmd_lore(args):
    import syl_ai as ai
    targets = core.load_all_entities() if args.all else [require(args.entity)]
    cap = spoiler_cap(args)
    for e in targets:
        if not core.visible_facts(e, cap):
            print(f"Skipping {e['name']}: no facts yet.")
            continue
        print(f"Writing lore for {e['name']}...")
        try:
            lore = ai.generate_lore(e, spoiler_chapter=cap)
        except ai.AIError as err:
            die(str(err))
        print(f"  {lore['description']}\n  {lore['biography']}\n  Tags: {', '.join(lore['lore_tags'])}")
        if args.dry_run:
            print("  (dry run, not saved)")
            continue
        e["ai_lore_enhancement"] = lore
        core.save_entity(e)
        print(f"  Saved ({lore['model']}).")


def cmd_settings(args):
    s = core.load_settings()
    if args.book is not None:
        s["current_book"] = args.book or None
    if args.chapter is not None:
        s["spoiler_chapter"] = args.chapter if args.chapter > 0 else None
    if args.lm_url:
        s["lm_studio_url"] = args.lm_url.rstrip("/")
    if args.model is not None:
        s["lm_model"] = args.model
    core.save_settings(s)
    for k, v in s.items():
        print(f"{k}: {v}")


# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="syl", description="SYL fantasy lore notebook",
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = p.add_subparsers(dest="cmd")

    def spoiler_opts(sp):
        sp.add_argument("--chapter-cap", type=int, help="override the spoiler chapter for this command")
        sp.add_argument("--all-chapters", action="store_true", help="ignore the spoiler shield")

    sp = sub.add_parser("list", help="list entities"); sp.add_argument("--type"); sp.add_argument("--book")
    spoiler_opts(sp); sp.set_defaults(fn=cmd_list)
    sp = sub.add_parser("show", help="show one entity"); sp.add_argument("entity"); spoiler_opts(sp)
    sp.set_defaults(fn=cmd_show)
    sp = sub.add_parser("search", help="search names, facts, tags"); sp.add_argument("query"); spoiler_opts(sp)
    sp.set_defaults(fn=cmd_search)
    sub.add_parser("stats", help="counts").set_defaults(fn=cmd_stats)

    sp = sub.add_parser("new", help="create an entity"); sp.add_argument("name")
    sp.add_argument("--type", default="Other", choices=core.ENTITY_TYPES + [t.lower() for t in core.ENTITY_TYPES])
    sp.add_argument("--book"); sp.add_argument("--chapter", type=int, default=1)
    sp.add_argument("--wikidata", action="store_true", help="also look it up on Wikidata")
    sp.set_defaults(fn=cmd_new)

    sp = sub.add_parser("fact", help="add a fact (quick entry)")
    sp.add_argument("entity"); sp.add_argument("chapter", type=int); sp.add_argument("text")
    sp.add_argument("--create", action="store_true", help="create the entity if missing")
    sp.add_argument("--type"); sp.set_defaults(fn=cmd_fact)

    sp = sub.add_parser("fetch", help="create or enrich an entity from Wikidata")
    sp.add_argument("query", help="a name or a QID like Q180322")
    sp.add_argument("--pick", type=int, help="choose the Nth search result")
    sp.add_argument("--yes", action="store_true", help="take the best match without asking")
    sp.add_argument("--book"); sp.set_defaults(fn=cmd_fetch)

    sp = sub.add_parser("import", help="bulk import from a text or JSON file")
    sp.add_argument("file"); sp.add_argument("--book"); sp.set_defaults(fn=cmd_import)

    sp = sub.add_parser("link", help="connect two entities")
    sp.add_argument("source"); sp.add_argument("target"); sp.add_argument("type")
    sp.add_argument("--desc"); sp.add_argument("--chapter", type=int); sp.set_defaults(fn=cmd_link)
    sp = sub.add_parser("unlink", help="remove a connection")
    sp.add_argument("source"); sp.add_argument("target"); sp.add_argument("--type"); sp.set_defaults(fn=cmd_unlink)
    sp = sub.add_parser("links", help="list connections"); sp.add_argument("entity", nargs="?")
    sp.set_defaults(fn=cmd_links)
    sp = sub.add_parser("mentions", help="entities named in this one's facts"); sp.add_argument("entity")
    spoiler_opts(sp); sp.set_defaults(fn=cmd_mentions)
    sp = sub.add_parser("resolve", help="add [[links]] to a piece of text"); sp.add_argument("text")
    sp.set_defaults(fn=cmd_resolve)

    sp = sub.add_parser("lore", help="AI biography from your facts (LM Studio)")
    sp.add_argument("entity", nargs="?"); sp.add_argument("--all", action="store_true")
    sp.add_argument("--dry-run", action="store_true"); spoiler_opts(sp); sp.set_defaults(fn=cmd_lore)
    sub.add_parser("ai-check", help="test the LM Studio connection").set_defaults(fn=cmd_ai_check)

    sp = sub.add_parser("settings", help="view or change settings")
    sp.add_argument("--book", help='current book ("" to clear)')
    sp.add_argument("--chapter", type=int, help="spoiler shield chapter (0 = off)")
    sp.add_argument("--lm-url"); sp.add_argument("--model", help='LM Studio model id ("" = auto)')
    sp.set_defaults(fn=cmd_settings)
    return p


def main(argv=None):
    p = build_parser()
    args = p.parse_args(argv)
    if not getattr(args, "fn", None):
        p.print_help()
        return
    if args.cmd == "lore" and not args.all and not args.entity:
        die("Name an entity, or use --all")
    args.fn(args)


if __name__ == "__main__":
    main()
