# SYL design direction

Process adapted from the "App Designer" skill (brief, three directions, pick
one, content first, render and check). Android, Flutter.

## Brief

Self-authored from the project and our conversations; correct anything wrong.

- **What and who:** a private, spoiler-safe notebook for one reader of long
  fantasy books (The Lord of the Rings, Mistborn). Used on an Android phone
  while reading, synced with the PC.
- **Core action (first ten seconds):** "who is this again?" Look someone up,
  or jot down what you just learned in this chapter. Both happen mid-chapter,
  one-handed, often in the evening.
- **Feel:** absorbed, a little magical, trustworthy (it must never spoil).
- **Exists already:** name SYL, Bricolage Grotesque, the spoiler shield,
  the map of links, AI lore from your own notes.
- **The one idea only SYL has:** the spoiler shield. Everything past your
  chapter is hidden. It should be felt, not just a setting.

## The category default we refuse

Reading apps (Goodreads, StoryGraph, Fable) share cream paper, a bookish
serif, book covers and warm brown or orange. Fantasy apps add parchment
texture, Cinzel or Trajan capitals, gold on black, dragons and blackletter.
SYL today is the "Calm Wellness" face: cream ground, five confetti pastels
assigned by id (colour that means nothing), rounded cards for everything, an
initial-in-a-circle on every row, a floating "+".

Refused: parchment, Cinzel/Trajan/blackletter, cream ground, colour by id,
a card around every group.

## Three concepts

| | A. Field atlas | B. Card table | C. Star chart |
|---|---|---|---|
| Concept | SYL is **an explorer's field atlas**: the book is a country, your chapter is where you are on the route, and past it the map is unsurveyed. | SYL is **a deck being dealt**: every character, place and thing you meet is a card dealt to you; anything past your chapter is still face down. | SYL is **a star chart of the book**: everyone you meet is a star, links are constellations, and what's past your chapter is still below the horizon. |
| Source family | place | play | nature |
| Ground | light (pale sea-grey paper) | colour field (green baize) | dark (night) |
| Type | serif display (Young Serif) + sans UI | condensed (Big Shoulders) + sans UI | expanded grotesque (Archivo Expanded) |
| Accent and its one job | vermilion: "you are here" (your chapter) | gold: "new this chapter" | starlight teal: what you can see now |
| Richness | illustration: contour lines and a dotted route | colour and material: baize, card stock, a sigil drawn from each name | shape: stars and constellation lines |
| Signature (spoiler shield) | fog over the map past your marker lifts when you move it on | the next chapter's cards flip face up | stars rise over the horizon |

## Exploration (round 1)

The Library screen three ways, same real content (The Lord of the Rings,
read to ch. 12, five entries, one fact hidden, two new this chapter):
`explore/sheet.png`, one PNG per direction, and `explore/explore.html`.

**Recommended: B, Card table.**

- The spoiler shield becomes something you can see and touch: what's past
  your chapter is literally face down, and moving to the next chapter turns
  cards over.
- Its richness is honest and grows with use: every entry gets a sigil drawn
  from its own name, so 200 entries are 200 different cards, with no
  invented artwork.
- A card is an object you pick up, so a card per entry is earned (unlike
  today's card around every group).
- The green baize is the most memorable ground of the three and unlike any
  reading app.

Why the others lost:

- **A, Field atlas:** the map would be invented decoration (SYL has no real
  geography for a book), and a serif on pale paper sits closest to the
  bookish category default.
- **C, Star chart:** beautiful, but the home screen would duplicate the Map
  tab, and the dark blue-green night drifts toward the sleep-app and sci-fi
  clichés. Its constellation idea could restyle the Map tab instead.

Risk in B to manage: baize reads as "casino" if pushed (no chips, no
felt texture photo, no gold foil).

## Exploration (round 2)

Feedback on round 1: keep C's constellations, but no cards; the home
screen should feel book or fantasy-book related. So all three below sit on
C's night ground with C's constellation Map (shared), and differ only in
the Library's metaphor. `explore/round2-sheet.png`, `explore/round2.html`.

| | D. Grimoire | E. Ribbon and contents | F. Dramatis personae |
|---|---|---|---|
| Concept | SYL is **your grimoire of the book**: each name is written in with its own sigil. | SYL is **the book's contents page**, and your ribbon bookmark marks how far you've read. | SYL is **the cast list** at the front of a fantasy novel, grouped by who travels together. |
| Type | Fraunces (display serif) + Archivo UI | Newsreader + Archivo UI | Archivo Expanded + Fraunces italic epithets |
| Accent and its one job | ember: "new this chapter" | ribbon crimson: your chapter | starlight teal: "new this chapter" |
| Richness | a sigil per entry, drawn as a small constellation from the name | dotted leaders to the chapter where you met them | epithets ("called Strider") and groupings |
| Signature (spoiler shield) | facts past your chapter are under a wax seal that breaks when you get there | the pages past your ribbon are uncut | lines past your chapter are not yet written |

**Recommended: D, Grimoire.** The constellation sigil ties the home screen
to the Map (each entry's star on the Map is drawn from the same name), so
the sky runs through the whole app instead of living on one tab. The wax
seal is the most tangible spoiler shield of the three. Risk: keep the seal
the only ornament (no parchment, no gold) so it stays out of fantasy cliché.

## Exploration (round 3)

Feedback on round 2: the constellation look is only for the Map tab; the
rest of the app shouldn't be star-themed. Keep it book or fantasy-book
related. The Map stays as in round 2. `explore/round3-sheet.png`,
`explore/round3.html`.

| | G. Illuminated chronicle | H. Library hardback | I. Traveller's journal |
|---|---|---|---|
| Concept | SYL is **a scribe's chronicle** of the book. | SYL is **your own library copy**: a cloth cover, a checkout slip, and an index at the back. | SYL is **the field notebook** of someone travelling through the story. |
| Ground | light vellum | navy book cloth, with the index on a page | dot-grid notebook paper |
| Type | EB Garamond | Libre Caslon + Courier Prime stamps | Literata + Caveat handwriting |
| Accent and its one job | rubric red: "new this chapter" | stamp purple: your chapter and "new" | pen blue: your own notes |
| Richness | an illuminated initial on every entry, chapters in roman numerals | blind-stamped title, the slip stamped at each chapter you reach | taped chapter tag, circled "new", margin notes |
| Signature (spoiler shield) | an initial the scribe hasn't painted yet | the rest of the index is clasped shut | the page is folded over |

**Recommended: H, Library hardback.** An index is already what you reach
for when you ask "who is this again?" It's alphabetical and gives the chapter
references, so the metaphor makes lookup better rather than just decorating it. The
checkout slip, stamped at each chapter you reach, is a natural "you are
here", and the clasp gives the spoiler shield something to hold. The
navy cloth also sits well next to the dark constellation Map.

Why the others lost: G's illuminated initial splits each name ("rodo
Baggins"), which slows scanning. I is charming, but the handwritten type
gets hard to read once notes are long.
