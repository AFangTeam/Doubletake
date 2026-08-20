# Doubletake

Compare two cameras, one subject, side by side — and export the result straight into your video.

English · [简体中文](README.zh-CN.md)

You went out with two bodies, or two lenses, and shot the same thing with both. Now you have to *show* someone the difference. That means finding the two frames that actually correspond, lining them up, zooming into the same corner of each, and getting it out as an image your editor can use.

Doubletake is built for that loop.

<!-- Screenshots to come. -->

## How it works

**1 · Point it at two folders.** Track A gets one camera's take, track B gets the other's. Every photo lands on a shared timeline by its EXIF capture time, so the two shoots line up chronologically instead of alphabetically.

**2 · Fix the clock drift.** Two cameras never agree on the time. One is thirty seconds fast; the other never left the factory timezone. Each track has its own time offset, dialed in with a jog wheel — drag to nudge, <kbd>Shift</kbd> for fine (10× slower), <kbd>Option</kbd> for coarse (10× faster), with a haptic tick as it crosses each whole second. Align once; the document remembers.

**3 · Find the pair.** From any photo, jump to the frame in the other track shot closest in time. That's usually the one you want.

**4 · Compare.** Both frames side by side. Zoom in and **pan both panes together** — hold <kbd>⌘</kbd> while dragging to move only one side when the framing doesn't match exactly. The EXIF overlay marks what actually *differs* between the two shots, so you're not eyeballing two full metadata dumps.

**5 · Export for the edit.** One command writes a named folder containing:

| File | What it is |
|---|---|
| `comparison.jpg` | Exactly what you're looking at — zoom and pan applied |
| `original_comparison.jpg` | Both frames untouched, laid out side by side |
| the two originals | Untouched, for the record |
| `comparison-info.json` | View parameters and EXIF summaries, so the frame can be reproduced later |

Exports target **4K video inserts**: roughly 8K on the long edge, JPEG at quality 0.92. (PNG at that resolution balloons to ~100 MB on photographic content for no visible gain.)

## Also does

- **Collapsible empty stretches** on the timeline, so a three-hour gap between sessions doesn't eat the whole view
- **Saved comparisons** — name an A/B pair, jump back to it later
- **Favorites** — heart the keepers, export them as a set
- **Trash originals** from inside the app; a RAW+JPG pair is one item, both files go together

## Formats

JPG/JPEG · HEIC/HEIF · PNG · TIFF · RAW (ARW, CR2, CR3, NEF, NRW, RAF, RW2, DNG, ORF, PEF, SRW, RWL, SRF)

A RAW and a JPG sharing a basename count as **one photo**, not two.

## Status

**Photos only.** Video files found while scanning are skipped and reported as a count — video support is deliberately out of scope for now.

This is a tool its author uses, not a shipped product. There's no signed build and no release yet, so you build it from source. The Xcode target is still named `Timeline`, from before the project had a name it deserved.

## Build

Requires **macOS 26** and Xcode with the macOS 26 SDK.

```bash
git clone https://github.com/AFangTeam/Doubletake.git
cd Doubletake
open Timeline.xcodeproj
```

Then ⌘R. Set your own signing team under the target's Signing & Capabilities.

## Documents

A `.timelinecompare` document is a package holding `compare.json` — track config, time offsets, favorites, saved comparisons — plus security-scoped bookmarks to the two folders, so reopening it restores access to the originals without picking them again. **Photos are never copied into the document.**

## License

[MIT](LICENSE)
