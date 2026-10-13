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
