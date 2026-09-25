"""
Wikidata lookups for SYL.

- search(name)          -> ranked candidates (id, label, description)
- fetch(qid)            -> the facts SYL keeps: label, description, aliases,
                           "instance of" labels and a guessed SYL type
- apply_to_entity(...)  -> merge those into an entity WITHOUT touching the
                           user's facts or AI lore

Wikidata never writes facts or chapters: it only fills external_data, the
type (if still "Other") and the name.
"""

from __future__ import annotations

import json
import ssl
import urllib.error
import urllib.parse
import urllib.request

from syl_core import guess_type

API = "https://www.wikidata.org/w/api.php"
ENTITY_DATA = "https://www.wikidata.org/wiki/Special:EntityData/{qid}.json"
# Wikimedia asks for a descriptive User-Agent.
USER_AGENT = "SYL/0.2 (personal fantasy reading companion)"

_ssl = ssl.create_default_context()  # certificate checks stay ON

class WikidataError(Exception):
    pass


def _get_json(url: str, params: dict | None = None) -> dict:
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"  # encodes spaces, accents etc.
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, context=_ssl, timeout=20) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise WikidataError(f"Wikidata returned HTTP {e.code}") from e
    except urllib.error.URLError as e:
        raise WikidataError(f"Could not reach Wikidata: {e.reason}") from e


FICTION_HINTS = ("fictional", "character", "legendarium", "middle-earth", "novel", "fantasy",
                 "series", "saga", "book")
# Adaptations share names with the book version; prefer the literary one.
ADAPTATION_HINTS = ("musical", "film", "television", "tv series", "video game", "opera", "stage",
                    "actor", "actress", "band", "album", "song")


def search(name: str, limit: int = 7, hint: str | None = None) -> list[dict]:
    """Candidates for a name. Fiction-looking results (and ones matching `hint`,
    e.g. the book title or author) float to the top; the original order breaks ties."""
    data = _get_json(API, {
        "action": "wbsearchentities", "search": name, "language": "en",
        "uselang": "en", "type": "item", "limit": limit, "format": "json",
    })
    results = []
    for i, hit in enumerate(data.get("search", [])):
        desc = hit.get("description", "") or ""
        score = 0
        low = desc.lower()
        if any(h in low for h in FICTION_HINTS):
            score += 2
        if any(h in low for h in ADAPTATION_HINTS):
            score -= 3
        if hint and any(w in low for w in hint.lower().split() if len(w) > 3):
            score += 1
        if hit.get("label", "").lower() == name.lower():
            score += 1
        results.append({"id": hit["id"], "label": hit.get("label", ""), "description": desc,
                        "_score": score, "_rank": i})
    results.sort(key=lambda r: (-r["_score"], r["_rank"]))
    for r in results:
        r.pop("_score"); r.pop("_rank")
    return results


def _labels(qids: list[str]) -> dict[str, str]:
    if not qids:
        return {}
    data = _get_json(API, {"action": "wbgetentities", "ids": "|".join(qids[:50]),
                           "props": "labels", "languages": "en", "format": "json"})
    out = {}
    for qid, ent in data.get("entities", {}).items():
        out[qid] = ent.get("labels", {}).get("en", {}).get("value", qid)
    return out


def fetch(qid: str) -> dict:
    qid = qid.strip().upper()
    data = _get_json(ENTITY_DATA.format(qid=qid))
    ents = data.get("entities", {})
    # Special:EntityData follows redirects, so the key may be a different QID.
    ent = ents.get(qid) or (next(iter(ents.values())) if ents else None)
    if not ent:
        raise WikidataError(f"{qid} not found on Wikidata")
    real_id = ent.get("id", qid)
    label = ent.get("labels", {}).get("en", {}).get("value") \
        or next(iter(ent.get("labels", {}).values()), {}).get("value", real_id)
    desc = ent.get("descriptions", {}).get("en", {}).get("value", "")
    aliases = [a["value"] for a in ent.get("aliases", {}).get("en", [])]
    p31 = []
    for claim in ent.get("claims", {}).get("P31", []):
        v = claim.get("mainsnak", {}).get("datavalue", {}).get("value", {})
        if isinstance(v, dict) and v.get("id"):
            p31.append(v["id"])
    instance_labels = list(_labels(p31).values())
    return {
        "id": real_id,
        "label": label,
        "description": desc,
        "aliases": aliases,
        "instance_of": instance_labels,
        "type": guess_type(instance_labels),
    }


def apply_to_entity(entity: dict, wd: dict) -> dict:
    """Fill Wikidata fields into an entity; user facts and AI lore are untouched."""
    ext = entity["external_data"]
    ext["wikidata_id"] = wd["id"]
    ext["description"] = wd["description"]
    ext["aliases"] = sorted(set(ext.get("aliases", [])) | set(wd["aliases"]))
    ext["instance_of"] = wd["instance_of"]
    if entity.get("type", "Other") == "Other":
        entity["type"] = wd["type"]
    if entity["metadata"].get("source") in (None, "", "manual"):
        entity["metadata"]["source"] = "wikidata"
    return entity
