# SYL: project state and handover

Last updated: 9 Oct 2026. Read this first in any new session. README.md covers usage.

## What SYL is

A spoiler-aware fantasy reading companion. The user records facts per chapter. SYL links entries together, enriches them from Wikidata, and uses the local LM Studio model to write lore from the user's notes only.

## Layout

| Path | What |
|---|---|
| `syl_core.py` | Data schema v2, load/save, merge, spoiler filtering. **The only code that touches data files.** |
| `syl_wikidata.py` | Wikidata search/fetch (URL-encoded, SSL verified, type from P31). Never writes facts. |
| `syl_ai.py` | LM Studio client plus the spoiler-safe lore prompt |
| `syl.py` | The single CLI (replaces the old per-feature scripts) |
| `syl_sync.py` | LAN sync: merge rules and the `syl.py serve` HTTP server. The PC is the hub. Also forwards the phone's AI calls (`/v1/models`, `/v1/chat/completions`) to LM Studio, so the phone uses the sync address for AI too |
| `tests/test_sync.py` | Python tests for the merge rules and the server |
| `migrate_data.py` | One-time v1 to v2 migration (already run; safe to rerun) |
| `mobile/lib/models/models.dart` | Dart mirror of the schema (tolerant parser, reads old formats) |
| `mobile/lib/data/storage.dart` | Data folder location and file IO |
| `mobile/lib/state/library_store.dart` | Single ChangeNotifier holding all app state |
| `mobile/lib/services/` | `wikidata_service.dart`, `ai_service.dart` (mirror the Python modules), `sync_service.dart` (client for `syl.py serve`) |
| `mobile/lib/ui/` | Bento design: library, entity, map, reading/settings, sheets |
| `_to_delete/` | Retired scripts and docs, kept for reference. Safe to delete. |

## Rules for changes

- The JSON schema is shared. If you change it, change `syl_core.py` **and** `models.dart` together, and bump `schema_version`.
- Keys are snake_case. Chapters are ints. Entity file name = `id` field.
- Relationships live only in `data/relationships.json`, never inside entity files.
- Every delete (entity, fact, link) must be recorded in `data/deleted.json` (`record_deletion` / `DeletedLog`), or a sync will bring it back.
- Merging happens only on the PC (`syl_sync.merge_libraries`). The app sends its library and stores whatever comes back.
- Wikidata and AI never overwrite or delete user facts.
- Everything that shows facts or sends them to the AI must go through the spoiler filter (`visible_facts` / `visibleFacts`).
- No Telegram or other notification code belongs in this project.
- After `flutter analyze` passes, run the app and open every screen. Analyze does not catch runtime state bugs.

## Known gaps / next ideas

- APKs come from GitHub Actions (`.github/workflows/android-apk.yml`, release `apk-latest`), signed with a throwaway debug key per build. Updating needs sync, uninstall, reinstall, sync until a permanent signing key is set up.

- Sync is manual: the user taps Sync now. The server must be running on the PC, and the PC is found by typing its IP address (no auto-discovery).
- Sync matches entries by id. The same character created on both devices under different ids (e.g. a slug on the phone, a Wikidata QID on the PC) ends up as two entries.
- Sync uses each device's clock to decide which edit is newer, so a phone and PC whose clocks disagree by a lot can pick the wrong one.
- `deleted.json` grows forever. It's small, but could be pruned after everyone has synced.
- AI only writes biographies. Possible next steps: extract facts from a pasted passage, answer "who is X?" from notes, suggest links.
- The map uses a simple ring layout. Fine for dozens of entries; it would need a force layout for hundreds.
