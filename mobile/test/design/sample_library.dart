import 'package:mobile/models/models.dart';
import 'package:mobile/state/library_store.dart';

/// A believable library for screenshots and design checks: uneven fact
/// counts, one entry with AI lore, one with nothing yet, a fact past the
/// spoiler chapter, two books, saved links and names mentioned in facts.
LibraryStore sampleLibrary() {
  const lotr = 'The Lord of the Rings';
  const mistborn = 'Mistborn: The Final Empire';
  var n = 0;
  Fact f(String text, int chapter) =>
      Fact(id: 'f${n++}', text: text, chapter: chapter, timestamp: '2026-10-0${1 + chapter % 9}T21:${10 + n}:00');
  EntityMeta meta(String day) => EntityMeta(firstSeen: day, lastUpdated: '${day}T21:40:00');

  return LibraryStore.memory(
    entities: [
      Entity(
        id: 'Q180322',
        name: 'Aragorn',
        type: 'Character',
        book: lotr,
        discoveryChapter: 10,
        facts: [
          f('Goes by Strider in Bree; the hobbits distrust him at first', 10),
          f('Carries the shards of Narsil, the sword that was broken', 10),
          f('Heir of Isildur, though he keeps it quiet', 12),
          f('Leads the hobbits through the Midgewater Marshes', 11),
          f('Takes the paths of the Dead', 47), // past the spoiler chapter
        ],
        lore: const Lore(
          biography: 'A ranger of the North who meets the hobbits at the Prancing Pony under the name Strider. '
              'He carries the broken sword Narsil and is the heir of Isildur, a claim he keeps to himself.',
          generatedAt: '2026-10-07T22:03:00',
          model: 'qwen3-8b',
          spoilerLimitChapter: 12,
        ),
        external: const ExternalData(
          wikidataId: 'Q180322',
          description: 'fictional character in Middle-earth',
          aliases: ['Strider'],
          safeFacts: ['People: Rangers of the North, Dúnedain', 'World: Tolkien\'s legendarium', 'Speaks: Westron, Sindarin'],
        ),
        meta: meta('2026-10-03'),
      ),
      Entity(
        id: 'Q177499',
        name: 'Gandalf',
        type: 'Character',
        book: lotr,
        discoveryChapter: 1,
        facts: [
          f('Brings fireworks to Bilbo\'s party', 1),
          f('Leaves a late letter for Frodo with Butterbur', 10),
        ],
        external: const ExternalData(wikidataId: 'Q177499', description: 'fictional character in Middle-earth'),
        meta: meta('2026-10-01'),
      ),
      Entity(
        id: 'frodo-baggins',
        name: 'Frodo Baggins',
        type: 'Character',
        book: lotr,
        facts: [
          f('Inherits Bag End and the Ring from Bilbo', 1),
          f('Uses the name Mr Underhill at the Prancing Pony', 9),
          f('Stabbed by a Morgul blade on Weathertop', 12),
        ],
        meta: meta('2026-10-01'),
      ),
      Entity(
        id: 'bree',
        name: 'Bree',
        type: 'Location',
        book: lotr,
        discoveryChapter: 9,
        facts: [f('Men and hobbits live side by side here', 9)],
        meta: meta('2026-10-02'),
      ),
      Entity(
        id: 'narsil',
        name: 'Narsil',
        type: 'Item',
        book: lotr,
        discoveryChapter: 10,
        meta: meta('2026-10-03'),
      ),
      Entity(
        id: 'vin',
        name: 'Vin',
        type: 'Character',
        book: mistborn,
        facts: [f('A street thief who hears a voice she calls Reen', 1)],
        meta: meta('2026-09-28'),
      ),
    ],
    relationships: const [
      Relationship(source: 'Q180322', target: 'frodo-baggins', type: 'Guide', chapter: 10, createdAt: '2026-10-03T21:50:00'),
      Relationship(source: 'Q180322', target: 'narsil', type: 'Carries', chapter: 10, createdAt: '2026-10-03T21:51:00'),
      Relationship(source: 'Q177499', target: 'Q180322', type: 'Old friend', chapter: 10, createdAt: '2026-10-04T21:30:00'),
    ],
    settings: const AppSettings(currentBook: lotr),
    books: const [
      Book(
        id: 'the-lord-of-the-rings',
        title: lotr,
        author: 'J. R. R. Tolkien',
        chapter: 12,
        totalChapters: 22,
        chapterNames: [
          'A Long-expected Party', 'The Shadow of the Past', 'Three is Company', 'A Short Cut to Mushrooms',
          'A Conspiracy Unmasked', 'The Old Forest', 'In the House of Tom Bombadil', 'Fog on the Barrow-Downs',
          'At the Sign of the Prancing Pony', 'Strider', 'A Knife in the Dark', 'Flight to the Ford', 'Many Meetings',
          'The Council of Elrond', 'The Ring Goes South', 'A Journey in the Dark', 'The Bridge of Khazad-dûm',
          'Lothlórien', 'The Mirror of Galadriel', 'Farewell to Lórien', 'The Great River', 'The Breaking of the Fellowship',
        ],
      ),
      Book(id: 'mistborn', title: mistborn, author: 'Brandon Sanderson', chapter: 5, totalChapters: 38),
      Book(id: 'the-hobbit', title: 'The Hobbit', author: 'J. R. R. Tolkien', status: 'finished', rating: 4.5),
      Book(id: 'elantris', title: 'Elantris', author: 'Brandon Sanderson', status: 'want'),
    ],
  );
}
