# SYL

A spoiler-aware reading companion for fantasy books. You note what you learn about characters, places and items as you read, chapter by chapter. SYL keeps it organised, links it together, pulls extra details from Wikidata, and can have the AI model on your PC write short lore from your notes, without spoiling anything past your chapter.

The project has two parts that share one data folder:

- `mobile/` is the Flutter app (Windows desktop and Android).
- `syl.py` is a command line tool for the same library.

## Data

```
data/
  entities/<id>.json   one file per entry (id = Wikidata QID, or a slug like frodo-baggins)
  relationships.json   links between entries
  settings.json        current book, spoiler chapter, LM Studio address
  _old_v1/             the pre-migration files, kept as a backup
```

The format is documented at the top of `syl_core.py`. The app and the CLI both read and write exactly this format.

On Windows the app uses `C:\Users\V\SYL_Project\data` directly, so the app and CLI see the same library. On a phone the app keeps its own copy in app storage. Syncing the phone and PC copies isn't built yet.

## The spoiler shield

Set your book and the chapter you've reached (the app's Reading tab, or `python syl.py settings --chapter 7`). Facts and links from later chapters are then hidden in every view and are never sent to the AI.

## AI (LM Studio on your PC)

1. In LM Studio, load a model, open the Developer tab and start the server (port 1234).
2. PC: nothing else to do. `python syl.py ai-check` confirms the connection.
3. Phone: turn on **Serve on Local Network** in LM Studio. In the app's Reading tab, set the address to `http://<PC IP>:1234` (currently `192.168.0.109`). Both devices must be on the same Wi-Fi. You may need to allow LM Studio through Windows Firewall.

The AI only sees your notes up to the spoiler chapter. It is told to ignore anything it already knows about the book, write only from those notes, and never invent events. SYL uses whichever model is loaded, unless you name one in settings.

## CLI

```
python syl.py list | show <name> | search <text> | stats
python syl.py new "Samwise Gamgee" --type Character --chapter 2 [--wikidata]
python syl.py fact Aragorn 7 "He drew his sword"
python syl.py fetch "Frodo Baggins"          # Wikidata: creates, or enriches without touching your facts
python syl.py import notes.txt               # text or JSON, see below
python syl.py link Galadriel Aragorn Mentor --desc "She guides him" --chapter 3
python syl.py links | mentions <name> | resolve "some text"
python syl.py lore Aragorn | lore --all | ai-check
python syl.py settings --book "The Lord of the Rings" --chapter 7
```

Bulk import text format:

```
Galadriel: Elf
Chapter 1: She is from Lothlórien
2: She guards the One Ring
---
Aragorn: Character
Chapter 1: He is the heir to the throne
```

## Running the app

```
cd mobile
flutter pub get
flutter run -d windows        # or an Android device
flutter test
```
