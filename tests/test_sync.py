"""Tests for LAN sync. Run: python -m unittest discover tests"""

import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

_TMP = tempfile.TemporaryDirectory()
os.environ["SYL_DATA_DIR"] = _TMP.name  # before syl_core is imported
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import syl_core as core  # noqa: E402
import syl_sync  # noqa: E402


def entity(eid, name, facts=(), updated="2026-10-01T10:00:00", **extra):
    e = core.new_entity(name, "Character", entity_id=eid)
    e["user_captured_facts"] = [
        {"id": fid, "text": text, "chapter": ch, "timestamp": "2026-10-01T09:00:00", "source": "user"}
        for fid, text, ch in facts
    ]
    e["metadata"]["last_updated"] = updated
    e.update(extra)
    return e


def rel(src, tgt, type_="Mentor", created="2026-10-01T10:00:00"):
    return {"source": src, "target": tgt, "type": type_, "description": "", "chapter": None, "created_at": created}


def lib(entities=(), relationships=(), deleted=None):
    return {"entities": list(entities), "relationships": list(relationships), "deleted": deleted or {}}


class MergeTests(unittest.TestCase):
    def test_union_of_both_sides(self):
        out = syl_sync.merge_libraries(lib([entity("aragorn", "Aragorn")]), lib([entity("Q1", "Galadriel")]))
        self.assertEqual([e["name"] for e in out["entities"]], ["Aragorn", "Galadriel"])

    def test_same_entity_keeps_facts_from_both_and_newer_fields(self):
        pc = entity("aragorn", "Aragorn", [("f1", "heir", 1)], updated="2026-10-01T10:00:00")
        phone = entity("aragorn", "Strider", [("f2", "ranger", 2)], updated="2026-10-02T10:00:00")
        out = syl_sync.merge_libraries(lib([pc]), lib([phone]))
        (e,) = out["entities"]
        self.assertEqual(e["name"], "Strider")
        self.assertEqual([f["id"] for f in e["user_captured_facts"]], ["f1", "f2"])

    def test_older_side_keeps_lore_and_wikidata_the_newer_lacks(self):
        old = entity("aragorn", "Aragorn", updated="2026-10-01T10:00:00")
        old["ai_lore_enhancement"]["biography"] = "A ranger."
        old["external_data"]["wikidata_id"] = "Q180322"
        new = entity("aragorn", "Aragorn", updated="2026-10-02T10:00:00")
        (e,) = syl_sync.merge_libraries(lib([old]), lib([new]))["entities"]
        self.assertEqual(e["ai_lore_enhancement"]["biography"], "A ranger.")
        self.assertEqual(e["external_data"]["wikidata_id"], "Q180322")

    def test_deleted_entity_stays_deleted(self):
        pc = lib([entity("frodo", "Frodo")])
        phone = lib(deleted={"entities": {"frodo": "2026-10-05T10:00:00"}})
        self.assertEqual(syl_sync.merge_libraries(pc, phone)["entities"], [])

    def test_entity_edited_after_deletion_survives(self):
        pc = lib([entity("frodo", "Frodo", updated="2026-10-06T10:00:00")])
        phone = lib(deleted={"entities": {"frodo": "2026-10-05T10:00:00"}})
        self.assertEqual(len(syl_sync.merge_libraries(pc, phone)["entities"]), 1)

    def test_deleted_fact_stays_deleted(self):
        pc = lib([entity("frodo", "Frodo", [("f1", "hobbit", 1), ("f2", "ring", 2)])])
        phone = lib([entity("frodo", "Frodo", [("f1", "hobbit", 1)], updated="2026-10-02T10:00:00")],
                    deleted={"facts": {"f2": "2026-10-02T10:00:00"}})
        (e,) = syl_sync.merge_libraries(pc, phone)["entities"]
        self.assertEqual([f["id"] for f in e["user_captured_facts"]], ["f1"])

    def test_links(self):
        ents = [entity("a", "Alpha"), entity("b", "Beta")]
        # union, de-duplicated by source/target/type
        out = syl_sync.merge_libraries(lib(ents, [rel("a", "b")]), lib(ents, [rel("a", "b", "mentor")]))
        self.assertEqual(len(out["relationships"]), 1)
        # deleted on one side
        gone = {"relationships": {"a|b|mentor": "2026-10-02T10:00:00"}}
        self.assertEqual(syl_sync.merge_libraries(lib(ents, [rel("a", "b")]), lib(ents, deleted=gone))["relationships"], [])
        # re-created after the deletion
        again = [rel("a", "b", created="2026-10-03T10:00:00")]
        self.assertEqual(len(syl_sync.merge_libraries(lib(ents, again), lib(ents, deleted=gone))["relationships"]), 1)
        # dangling links are dropped
        self.assertEqual(syl_sync.merge_libraries(lib(ents[:1], [rel("a", "b")]), lib())["relationships"], [])

    def test_bad_ids_are_ignored(self):
        bad = entity("ok", "Fine")
        bad["id"] = "../../evil"
        self.assertEqual(syl_sync.merge_libraries(lib([bad]), lib())["entities"], [])

    def test_merge_is_symmetric(self):
        a = lib([entity("x", "X", [("f1", "one", 1)])], [rel("x", "y")])
        b = lib([entity("y", "Y"), entity("x", "X2", [("f2", "two", 2)], updated="2026-10-03T00:00:00")])
        self.assertEqual(syl_sync.merge_libraries(a, b), syl_sync.merge_libraries(b, a))


class CoreTombstoneTests(unittest.TestCase):
    def setUp(self):
        for f in Path(_TMP.name).rglob("*.json"):
            f.unlink()

    def test_deletes_are_recorded(self):
        core.save_entity(entity("a", "Alpha"))
        core.save_entity(entity("b", "Beta"))
        core.add_relationship("a", "b", "Mentor")
        core.remove_relationship("a", "b")
        core.delete_entity("a")
        d = core.load_deleted()
        self.assertIn("a", d["entities"])
        self.assertIn("a|b|mentor", d["relationships"])


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        syl_sync.SyncHandler.code = "123456"
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), syl_sync.SyncHandler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def setUp(self):
        for f in Path(_TMP.name).rglob("*.json"):
            f.unlink()

    def call(self, path, body=None, code="123456"):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, headers={"X-SYL-Code": code})
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())

    def test_wrong_code_is_refused(self):
        with self.assertRaises(urllib.error.HTTPError) as cm:
            self.call("/ping", code="000000")
        self.assertEqual(cm.exception.code, 401)

    def test_round_trip(self):
        core.save_entity(entity("aragorn", "Aragorn", [("f1", "heir", 1)]))
        core.save_entity(entity("frodo", "Frodo"))
        self.assertEqual(self.call("/ping")["entities"], 2)

        phone = lib([entity("Q1", "Galadriel", [("f9", "elf", 1)])],
                    deleted={"entities": {"frodo": "2099-01-01T00:00:00"}})
        out = self.call("/sync", {"schema_version": 2, **phone})

        self.assertEqual([e["id"] for e in out["entities"]], ["aragorn", "Q1"])
        self.assertEqual(sorted(e["id"] for e in core.load_all_entities()), ["Q1", "aragorn"])
        self.assertIn("frodo", core.load_deleted()["entities"])
        self.assertTrue((core.DATA_DIR / "_sync_backup" / "entities" / "frodo.json").exists())

        # A second sync with the result changes nothing.
        again = self.call("/sync", {"schema_version": 2, **out})
        self.assertEqual(again["entities"], out["entities"])


class LmStudioProxyTests(unittest.TestCase):
    """The sync server passes the app's AI calls on to LM Studio on the PC."""

    @classmethod
    def setUpClass(cls):
        from http.server import BaseHTTPRequestHandler

        class FakeLmStudio(BaseHTTPRequestHandler):
            def do_GET(self):
                self._reply({"data": [{"id": "qwen"}]} if self.path == "/v1/models" else {"error": "nope"},
                            200 if self.path == "/v1/models" else 404)

            def do_POST(self):
                sent = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                self._reply({"choices": [{"message": {"content": "echo " + sent["model"]}}]}, 200)

            def _reply(self, body, status):
                data = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *a):
                pass

        cls.lm = ThreadingHTTPServer(("127.0.0.1", 0), FakeLmStudio)
        threading.Thread(target=cls.lm.serve_forever, daemon=True).start()
        syl_sync.SyncHandler.code = "123456"
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), syl_sync.SyncHandler)
        cls.base = f"http://127.0.0.1:{cls.httpd.server_address[1]}"
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        for s in (cls.httpd, cls.lm):
            s.shutdown()
            s.server_close()

    def set_lm_url(self, url):
        s = core.load_settings()
        s["lm_studio_url"] = url
        core.save_settings(s)

    def test_models_and_chat_are_passed_on(self):
        self.set_lm_url(f"http://127.0.0.1:{self.lm.server_address[1]}")
        with urllib.request.urlopen(self.base + "/v1/models", timeout=5) as r:
            self.assertEqual(json.loads(r.read())["data"][0]["id"], "qwen")
        req = urllib.request.Request(self.base + "/v1/chat/completions", data=json.dumps({"model": "qwen"}).encode())
        with urllib.request.urlopen(req, timeout=5) as r:
            self.assertEqual(json.loads(r.read())["choices"][0]["message"]["content"], "echo qwen")

    def test_lm_studio_down_gives_a_clear_error(self):
        self.set_lm_url("http://127.0.0.1:9")
        with self.assertRaises(urllib.error.HTTPError) as cm:
            urllib.request.urlopen(self.base + "/v1/models", timeout=5)
        self.assertEqual(cm.exception.code, 502)
        self.assertIn("can't reach LM Studio", json.loads(cm.exception.read())["error"])

    def test_other_paths_are_not_passed_on(self):
        with self.assertRaises(urllib.error.HTTPError) as cm:
            urllib.request.urlopen(self.base + "/v1/embeddings", timeout=5)
        self.assertEqual(cm.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
