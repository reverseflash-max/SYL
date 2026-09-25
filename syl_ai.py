"""
AI lore for SYL, using the model loaded in LM Studio on your PC.

LM Studio exposes an OpenAI-compatible server (Developer tab > Start Server,
default http://127.0.0.1:1234). To use it from the phone, turn on
"Serve on Local Network" in LM Studio and point the app at http://<PC-IP>:1234.

Spoiler safety: the model only ever sees facts at or before the spoiler
chapter, and is told to ignore anything it already knows about the book.
"""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request

import syl_core as core


class AIError(Exception):
    pass


SYSTEM_PROMPT = (
    "You write short lore notes for a reader's private fantasy notebook. "
    "STRICT RULES: use ONLY the notes you are given. Do not add anything you may already "
    "know about the book, film, or character, even if you recognise the name: the reader "
    "has not read that far and outside knowledge is a spoiler. If the notes are thin, "
    "write less. Never invent events, relatives, titles or fates."
)


def _request(url: str, payload: dict | None = None, timeout: int = 120) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method="POST" if data else "GET",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:300]
        raise AIError(f"LM Studio returned HTTP {e.code}: {body}") from e
    except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
        raise AIError(
            f"Can't reach LM Studio at {url}. Start the server in LM Studio "
            f"(Developer tab) and load a model. ({e})") from e


def list_models(base_url: str) -> list[str]:
    data = _request(base_url.rstrip("/") + "/v1/models", timeout=8)
    return [m.get("id") for m in data.get("data", []) if m.get("id")]


def pick_model(base_url: str, preferred: str = "") -> str:
    models = list_models(base_url)
    if not models:
        raise AIError("LM Studio is running but no model is loaded.")
    if preferred:
        for m in models:
            if m == preferred or preferred.lower() in m.lower():
                return m
    # Skip embedding models if any are loaded alongside the chat model.
    chat = [m for m in models if "embed" not in m.lower()]
    return (chat or models)[0]


def chat(base_url: str, model: str, system: str, user: str,
         temperature: float = 0.4, max_tokens: int = 700) -> str:
    data = _request(base_url.rstrip("/") + "/v1/chat/completions", {
        "model": model,
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": temperature,
        "max_tokens": max_tokens,
        # Reasoning models (Qwen 3.5 etc.) otherwise spend the whole budget
        # "thinking" and return nothing. Non-reasoning models ignore this.
        "reasoning_effort": "none",
        "stream": False,
    }, timeout=300)
    try:
        choice = data["choices"][0]
        text = choice["message"].get("content") or ""
    except (KeyError, IndexError) as e:
        raise AIError(f"Unexpected reply from LM Studio: {str(data)[:200]}") from e
    if not text.strip() and choice.get("finish_reason") == "length":
        raise AIError("The model used its whole token budget thinking and wrote nothing. "
                      "Turn off reasoning for this model in LM Studio, or pick a non-reasoning model.")
    # Reasoning models (Qwen 3.x etc.) may include their thinking.
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()


def _extract_json(text: str) -> dict:
    text = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.MULTILINE).strip()
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if not m:
        raise AIError("The model did not return JSON. Try again, or try a different model.")
    try:
        return json.loads(m.group())
    except json.JSONDecodeError as e:
        raise AIError(f"The model returned broken JSON: {e}") from e


def build_prompt(entity: dict, facts: list[dict], related: list[str]) -> str:
    lines = [f"Name: {entity['name']}", f"Type: {entity['type']}"]
    if entity.get("book"):
        lines.append(f"Book: {entity['book']}")
    lines.append("")
    lines.append("Reader's notes (chapter: note):")
    for f in facts:
        lines.append(f"- Ch {f['chapter']}: {f['text']}")
    if related:
        lines.append("")
        lines.append("Known connections:")
        lines += [f"- {r}" for r in related]
    lines += [
        "",
        "Return ONLY a JSON object with these keys:",
        '  "description": one sentence (max 30 words) summing up who/what this is,',
        '  "biography": 2-4 sentences in an evocative fantasy-narrator voice, built only from the notes,',
        '  "tags": 3-6 short tags (1-2 words each) that the notes clearly support.',
    ]
    return "\n".join(lines)


def generate_lore(entity: dict, *, settings: dict | None = None,
                  spoiler_chapter: int | None = None) -> dict:
    """Return a new ai_lore_enhancement dict (does not save)."""
    settings = settings or core.load_settings()
    cap = spoiler_chapter if spoiler_chapter is not None else settings.get("spoiler_chapter")
    facts = core.visible_facts(entity, cap)
    if not facts:
        raise AIError("No facts to work from yet (within your spoiler limit). Add a fact first.")

    entities = {e["id"]: e for e in core.load_all_entities()}
    related = []
    for r in core.load_relationships():
        if cap is not None and r.get("chapter") and r["chapter"] > cap:
            continue
        if r["source"] == entity["id"] and r["target"] in entities:
            related.append(f"{r['type']} of {entities[r['target']]['name']}")
        elif r["target"] == entity["id"] and r["source"] in entities:
            related.append(f"{entities[r['source']]['name']} is {r['type']} of this entity")

    base = settings.get("lm_studio_url") or core.DEFAULT_SETTINGS["lm_studio_url"]
    model = pick_model(base, settings.get("lm_model", ""))
    reply = chat(base, model, SYSTEM_PROMPT, build_prompt(entity, facts, related))
    data = _extract_json(reply)

    tags = data.get("tags") or data.get("lore_tags") or []
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",")]
    return {
        "description": str(data.get("description", "")).strip(),
        "biography": str(data.get("biography", "")).strip(),
        "lore_tags": [str(t).strip() for t in tags if str(t).strip()][:6],
        "generated_at": core.now_iso(),
        "model": model,
        "spoiler_limit_chapter": cap if cap is not None else max(f["chapter"] for f in facts),
    }
