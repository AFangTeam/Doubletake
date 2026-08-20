# Timeline

Compare two folders of photos on one shared time axis.

English · [简体中文](README.zh-CN.md)

Point track A at one folder and track B at another. Every photo lands on a shared timeline by its EXIF capture time, so two shoots line up against each other chronologically instead of alphabetically. Pick one frame from each track and compare them side by side, with the EXIF differences highlighted.

<!-- Screenshot goes here. -->

## Why the time offset matters

Two cameras never agree on the time. One is thirty seconds fast, the other never left the factory timezone — and suddenly your two tracks are shifted apart and nothing lines up.

So each track has its own time offset, dialed in with a jog wheel: drag to nudge, hold <kbd>Shift</kbd> for fine (10× slower), hold <kbd>Option</kbd> for coarse (10× faster). It ticks haptically as it crosses each whole second. Line the two tracks up once and the document remembers.

## What it does

- **Two tracks on a shared timeline**, ordered by EXIF capture time, with collapsible empty stretches so a three-hour gap doesn't eat the whole view
- **Per-track time offset** via jog wheel, for cameras whose clocks disagree
- **Cross-track jump** — from any photo, go to the one in the other track shot closest in time
- **A/B compare** — select one frame from each track and view them side by side
- **EXIF diff highlighting** — the metadata overlay marks what actually differs between the two frames
- **Saved comparisons** — name an A/B pair, jump back to it later
- **Favorites** — heart the keepers, export them as a set
- **Export a comparison** as a single image
- **Trash originals** from inside the app; a RAW+JPG pair is handled as one item, both files go together

## Formats

JPG/JPEG · HEIC/HEIF · PNG · TIFF · RAW (ARW, CR2, CR3, NEF, NRW, RAF, RW2, DNG, ORF, PEF, SRW, RWL, SRF)

A RAW and a JPG with the same basename are treated as **one photo**, not two.

## Status

**Photos only.** Video files in a scanned folder are skipped and reported as a count — video support is deliberately out of scope for now.

This is a working tool the author uses, not a shipped product: there is no signed build or release, so you build it from source.

## Build

Requires **macOS 26** and Xcode with the macOS 26 SDK.

```bash
git clone https://github.com/AFangTeam/Timeline.git
cd Timeline
open Timeline.xcodeproj
```

Then ⌘R. You will need to set your own signing team in the target's Signing & Capabilities tab.

## Documents

The app is document-based. A `.timelinecompare` document is a package holding `compare.json` (track config, time offsets, favorites, saved comparisons) plus security-scoped bookmarks to the two folders — so reopening a document restores access to the originals without re-picking them. **Photos are never copied into the document.**

## License

[MIT](LICENSE)
