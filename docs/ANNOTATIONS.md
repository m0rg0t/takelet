# Callouts and masks

Available in the source build after 0.1.0. The published 0.1.0 DMG does not include
these controls. Requires macOS 15+ on Apple Silicon; no provider key is needed.

## Edit a browser demo

1. Import or open a recording and scrub to the action you want to explain.
2. Open **Markup** in the inspector. Add an arrow, frame, text label, blur mask or
   opaque mask. New annotations start at the source playhead and last up to three
   seconds within the current retained interval.
3. Set **Start** and **End** in original source seconds. **Use Entire Take** is
   useful for a private address or account name that stays in the same location.
4. Choose **Place on Frame…**. Drag the outline and its corners on the original
   frame. The final video applies the recording's zooms and framing afterward.
   Use **Position & size** for exact values as percentages of the original frame.
5. Adjust color, arrow direction, line width, text size or blur strength. Text is
   white on a colored plate; it wraps and shrinks to fit. Enlarge the box or shorten
   the label if it cannot fit.
6. Apply, then scrub the composed preview across the whole interval. Save the
   project and export 1080p or 4K MP4.

The orange timeline track shows source intervals. When annotations overlap, use
the inspector picker to select one. **Duplicate**, **Backward** and **Forward**
adjust composition; reordering stays within the callout or mask layer. Masks always
cover callouts and cursors. Applied changes support Undo/Redo. Pending controls stay
with the document when you switch tabs or annotations; Save/Export apply them together.

## Timing and privacy

Visibility uses `[start, end)` source seconds. Removed footage removes its
annotations; restoring a cut restores them. Narration holds keep the annotation
on the frozen source frame. Overlapping annotations are supported; the limit is
64 per project, with up to 500 characters in each text label.

Masks are static rectangles anchored to the source, with no motion tracking or
fade animation. They follow the source through zooms. Review the full interval if
private content moves. **Opaque masks** fully cover pixels in the exported video;
**blur** softens details. The original recording and project media remain unredacted.

The project format is now 4. Formats 1–3 open with their appearance intact and no
annotations. Saving upgrades the format; older Takelet builds reject it.

## Validation

Core and workspace tests cover migration, intervals, geometry, overlap, source/output
mapping, portable saves, draft persistence and atomic application, and Undo/Redo.
Run native rendering checks with:

```sh
sh scripts/swift-check.sh build
TAKELET_BIN_DIR="${TMPDIR:-/private/tmp}/takelet-swift/build/debug"
"$TAKELET_BIN_DIR/takelet-media-check" --annotations artifacts/annotation-check-01
```

Use a new directory. The fixture is generated locally; Homebrew ffmpeg creates a
synthetic MP3 for the narration-hold check. The editor itself uses native macOS
frameworks. See [Testing](TESTING.md) for measured results and remaining manual checks.
