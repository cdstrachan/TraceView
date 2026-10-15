# TraceView
NOTE: This is a fork of https://github.com/thefinder808/TraceView

## Changes in this fork

Additions on top of the upstream project:

- **Open Recent menu** — the last 10 opened log files are remembered across launches and listed under *File → Open Recent*, with a *Clear Menu* option.
- **Severity row colouring** — log rows are tinted by severity (critical, error, warning) consistently across the Console, Light, Dark and Neon themes, and the severity summary chips use matching per-level colours. This is configurable via the theme menu.
- **Theme-coloured histogram bars** — error, warning and info segments in the histogram use the active theme's severity colours.
- **Full date in timestamps** — the timestamp column shows `yyyy-MM-dd HH:mm:ss.SSS` instead of time only.
- **Python logging timestamps** — the plain-text and delimited-log parsers accept comma-separated milliseconds (e.g. `2026-04-06 10:23:01,442`), as written by Python's `logging` module.
- **Resizable histogram** — drag the handle under the histogram to make it taller (28–180 pt); the height is remembered.
- **Histogram hover times** — moving across the histogram shows the time range of the slot under the pointer, and the tooltip shows the full date/time range plus event count.
- **Histogram zoom** — drag across a time range to zoom into it, or scroll the mouse wheel over the strip (up zooms in around the cursor, down zooms out a level). The histogram re-buckets into 60 slots for the zoomed range, in both in-memory and indexed (large-file) modes.
- **Zoom Out / Zoom All controls** — step back one zoom level or reset to the full time range. The selected range is shown while dragging, and the start, end and centre labels share the same larger font.
- **Readable parsed details** — the bottom detail pane pretty-prints full JSON records (or JSON messages in text logs) with darker, theme-aware syntax colors for keys, strings, numbers, and literals, and displays CSV records as labeled fields using the file's headers. JSON inside CSV fields is also formatted and colored. Copy preserves the displayed formatting as plain text; Raw still shows and copies the original record.
- **Full JSON in the grid** — structured JSON and unified-log rows show the complete raw record in the Message column, while parsed metadata and the bottom detail pane remain available.
- **Resizable bottom detail pane** — drag the handle above the record details up or down to resize the pane. Its height is remembered across launches and adapts to the window size while keeping the log grid visible.
- **Resizable sidebar** — drag the right edge of the files-and-bookmarks sidebar to adjust its width (180–300 pt), with a resize cursor and a larger grab area. The width is remembered across launches.
- **Flexible delimited logs** — local files (including `.gz`) auto-detect comma, semicolon, tab, and pipe separators. The status-bar format menu lets you choose a separator, including hyphen or a custom single character, and remembers the choice per file. Headers are detected automatically; headerless logs infer timestamp, severity, and message columns, with generic `Column N` labels in details. Use *First row → Headers / No headers* to correct ambiguous detection. When the file has a header row, column titles use the file's own header names. The grid shows every field of the file in its original order (no separate Component column), titled from the header row or `Column N`; column order can't be dragged for delimited files, and you can scroll horizontally when they don't fit. Raw records remain unchanged and exports still use standard comma-separated CSV.
- **Clickable following status** — click *Following* or *Not following* at the bottom right to toggle auto-scroll for that pane. Resuming jumps to the latest lines; scroll-synced panes toggle together. Live-stream ingestion remains controlled separately by *Pause / Resume*.
- **Clear Filters** — use *Filter → Clear Filters* or right-click the log grid (including empty space) to reset text, severity, component, and merged-source filters for that pane. Regex and case-sensitive options reset too; saved presets and the Filter/Find mode are unchanged.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg?logo=apple)](#requirements)
[![Buy the original author a Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/thefinder808)

A native macOS log viewer for admins, developers, and anyone who reads too many log files. Inspired by Microsoft's CMTrace.

Real-time file following, severity-aware highlighting, built-in error-code lookup, and a Console.app-style browser for system reports — all in a SwiftUI interface that feels at home on macOS 14+. A memory-mapped index keeps multi-gigabyte logs scrolling at 60 fps without ever loading them into RAM.

<p align="center">
  <img src="docs/screenshot.gif" alt="TraceView in motion: split view live-tailing two log files side-by-side with severity summary chips, density histograms, and a sidebar browsing /var/log plus crash/diagnostic/spin reports" width="900"/>
</p>

## Features

- **Real-time following** — new lines auto-scroll into view. Scroll up to investigate, scroll back down to resume. Kernel-level file watching (`DispatchSource`), no polling.
- **Multi-gigabyte files** — files at or above 100 MB open in a memory-mapped *indexed mode*: the file is `mmap`'d and an offset index is built up front, so rows are decoded and parsed lazily on demand (LRU-cached) instead of loading the whole file into RAM. Severity counts and the density histogram come from compact parallel index arrays, and text/level filtering runs on a background raw-byte scanner — so a 5 GB syslog stays at 60 fps. The mode is auto-selected by file size; smaller files use the eager in-memory path. Available for line-stateless formats (PlainText, SCCM, CSV).
- **Severity highlighting** — errors get red row backgrounds, warnings get yellow, critical rows are deeper red. Detected from structured formats (`messageType`, JSON `level`, SCCM `type`) and fallback keyword heuristics for plain text.
- **Severity summary chips** — live per-level counts (`Critical 4 · Error 127 · Warning 342 · …`). Click to filter.
- **Event histogram** — 60-bucket density strip above the table, stacked error/warn bars, trailing "now" marker. **Click any bucket to jump to that moment** — the click lands on the highest-severity entry in the bucket so a click on a red spike actually opens an error. **Spike preservation** keeps live-tail histograms readable: as the time range stretches, earlier spikes leave a faint shadow at their original height instead of fading into the noise floor. **Zoom** by dragging across a time range or scrolling the mouse wheel over the strip (up zooms in around the cursor, down zooms out a level); **Zoom Out** and **Zoom All** step back. Hover shows each slot's time range, and the strip's height can be dragged larger. Auto-hides when timestamps aren't parseable.
- **Expand-in-place drawer** — single-click any row to expand it with metadata, full message, and action pills (`Copy`, `Filter to component`, `Lookup error code`). Switchable to a bottom detail pane in Settings.
- **Error-code lookup inspector** — built-in database spanning 13 domains: `errno`, `OSStatus`, `IOReturn`, Mach `kern_return_t`, HTTP status, CFNetwork, Cocoa (`NSError`), Security (`errSec`), POSIX signals, SQLite result codes, gRPC status, Bonjour / DNS-SD, and POSIX exit codes (`sysexits.h`). Accepts decimal, hex, symbolic, or auto-detect input, with conservative cross-domain prioritization when the input is ambiguous. Inline error codes in log messages are tappable.
- **Saved filter presets** — snapshot the current filter to a named pill in the filter bar. Persisted.
- **Tabs** — multiple logs open in tabs with live-stream pulse dot.
- **Split view with scroll-sync** — open two logs side by side, with optional pane scroll-sync (⇧⌘S) so scrolling one pane drives the other to the closest matching timestamp. Following state mirrors across panes when sync is on. Active pane is marked with a 2px theme-tinted top accent strip; menu shortcuts (⌘F, ⌘G, ⇧⌘G, ⌘D, ⌘⌥R) route to whichever pane has focus — set via row click, tab click, or filter-bar focus.
- **Merged log view** — combine 2+ open logs into a single timeline sorted by timestamp. Each row tagged with its source; right-click to jump back to the original log. Per-source filter chips, drop-untimestamped, live-append from any source.
- **Console-style sidebar** — browse `/var/log`, `~/Library/Logs`, `/Library/Logs`, plus `.ips` reports split into Crash / Diagnostic / Spin buckets by filename classification (same rule Console.app uses). Right-click any report to open it directly in the left or right pane.
- **Bookmarks** — ⌘D bookmarks the selected row. The sidebar's Bookmarks section aggregates across every open doc, grouped by file, so you can jump back to any marked line regardless of which tab is active. Hover any bookmark for a one-click ✕ remove.
- **Live unified log** — wraps `log stream --style ndjson` for real-time system log capture with optional predicate filtering.
- **Multiple parsers** — PlainText, UnifiedLog (`log show/stream` JSON), JSONLines (including whole-file arrays), CSV, SCCM, IPS crash reports, and `.diag` diagnostic reports. Auto-detected by scoring the first ~50 lines of each file. `.gz` rotated logs are decompressed transparently on open.
- **Themes** — Console (default), Light, Dark, Neon.
- **Auto-update** — checks for new versions on launch and every 24 hours via [Sparkle](https://sparkle-project.org/), downloads + verifies them (Developer ID + EdDSA signatures), installs after a confirm prompt, and relaunches. Toggle in Settings → Updates, or check manually from the *About TraceView* menu.
- **Keyboard shortcuts** — `Cmd+O` open · `Cmd+Shift+O` open in right pane · `Cmd+F` search · `Cmd+G` / `Cmd+Shift+G` next/previous match · `Cmd+L` go to line · `Cmd+D` toggle bookmark · `Cmd+Opt+R` toggle regex matching · `Cmd+Shift+L` error lookup · `Cmd+\` toggle split view · `Cmd+Shift+S` toggle pane sync · `Cmd+Shift+E` export · `Cmd+K` command palette · `Cmd+T` cycle theme. Full list in [spec.md](spec.md#keyboard-shortcuts).

### Delimited log formats

Open a header-based file such as `timestamp;level;message` followed by
`2026-10-15 12:00:00;info;"Started; waiting"` and TraceView detects the
semicolon separator without splitting the quoted message. Headerless records
such as `2026-10-15 12:00:00|error|Connection failed` are also detected.

For less common separators, open the **format menu in the status bar** and
choose a preset or **Custom separator…**. Hyphen is manual-only so dates and
ordinary text are not mistaken for delimited records. Separator and first-row
preferences are saved for the original file, including compressed files.
**Automatic format** clears both overrides. These controls apply to local
files, not live streams or merged documents (configure their original files).
Each record must occupy one physical line; multiline quoted records are not
supported. Newlines and double quotes cannot be custom separators.

## Screenshots

<table>
  <tr>
    <td><img src="docs/screenshots/split-sync.png" alt="Split view with scroll-sync enabled"/></td>
    <td><img src="docs/screenshots/combined-view.png" alt="Merged log view combining two logs into one timeline"/></td>
  </tr>
  <tr>
    <td align="center"><sub>Split view with scroll-sync — both panes locked to the same timestamp</sub></td>
    <td align="center"><sub>Merged log view — two logs combined into a single sorted timeline with per-source filters</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/split-dual-filter.png" alt="Split view with independent filters in each pane"/></td>
    <td><img src="docs/screenshots/split-err-filter.png" alt="Split view with an ERROR-level filter applied to both panes"/></td>
  </tr>
  <tr>
    <td align="center"><sub>Split view with independent filters per pane</sub></td>
    <td align="center"><sub>Filtered to errors — histogram shows the cluster</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/dark-theme.png" alt="TraceView in the Dark theme"/></td>
    <td><img src="docs/screenshots/single-err-filter.png" alt="Single pane with histogram and error filter"/></td>
  </tr>
  <tr>
    <td align="center"><sub>Dark theme</sub></td>
    <td align="center"><sub>Single pane — histogram and severity chips up close</sub></td>
  </tr>
</table>

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9 toolchain (ships with Xcode 15+)

## Build

```sh
./build.sh run       # build .app and run with stdout visible (dev loop)
./build.sh app       # build debug .app bundle → build/TraceView.app
./build.sh release   # build release .app bundle
./build.sh install   # build release and copy to /Applications
./build.sh clean     # nuke build artifacts
```

`./build.sh run` is the normal dev command. It compiles with SPM, assembles a real `.app` around the binary, ad-hoc code-signs it, and execs the binary directly so `print()` output stays in your terminal. Running inside a proper bundle matters — some AppKit/SwiftUI APIs (menu bar, UserDefaults domain, TCC prompts, window restoration) misbehave for bare binaries.

## Architecture

```
Sources/
  TraceViewApp/          @main thin executable shell
  TraceViewCore/         all app logic, built as a unit-testable library
    App/                 scenes, commands, AppState, SettingsManager
    Models/              LogEntry, LogLevel, LogDocument, LogFilter, LogFilterPreset,
                         EntrySource (+ InMemoryEntrySource), IndexedEntrySource,
                         FilteredEntries, LogHistogram, HighlightRule, ErrorDomain
    Parsing/             LogParser protocol + seven built-in parsers + auto-detect
    Services/            FileWatcher, UnifiedLogStream, ErrorCodeLookup,
                         LogBrowserService, ExportService, GzipDecompressor,
                         LogIndex, IndexedFilterScanner, FastLineScanner
    ViewModels/          LogDocumentViewModel, ErrorLookupViewModel
    Theme/               AppTheme protocol, ThemeManager, Console/Light/Dark/Neon
    Utilities/           LRUCache, Formatters, Color+Hex, LoadPerfTimer
    Views/
      Components/        CommandPalette, StatusBarView, LogLevelBadge, HoverTooltip
      Sidebar/           SidebarView (Open Files / Reports / System Logs)
      LogView/           LogScrollView (custom AppKit virtual-scroll renderer),
                         FilterBarView, SeveritySummaryBar, HistogramView,
                         TabBarView, FilterPresetsView, InlineRowDetailView,
                         DetailPaneView, GoToLineSheet
      ErrorLookup/       ErrorLookupPanel
      ContentView, WelcomeView, SettingsView, CreateMergedViewSheet
```

The log table is a custom AppKit-backed virtual-scroll view (`LogScrollView`) wrapped via `NSViewRepresentable` — SwiftUI's `LazyVStack` can't keep up with 100K+ line files or live-tail bursts, so only the visible rows are ever realized. For files at or above 100 MB, `LogDocument` auto-dispatches to an `IndexedEntrySource` (memory map + offset index, see `LogIndex`) so rows parse on demand rather than all up front. App logic lives in the `TraceViewCore` library so it can be unit-tested; `TraceViewApp` is a thin `@main` shell. Everything else is pure SwiftUI.

Full design + feature spec in [spec.md](spec.md).

## Big files (indexed mode)

Files at or above 100 MB are loaded with a memory-mapped index instead of read into RAM. A 5 GB BSD-syslog file goes from "can't open" to:

- First open: ~5 s (one-shot byte-level scan + index cache write)
- Subsequent opens: ~200 ms (cache hit)
- Scrolling: 60 fps anywhere in the file
- Filter (text + level + component): ~2 s with progress
- Severity chips + histogram: instant; click any histogram bar to jump

Everything else still works the same — the indexed path just doesn't need the file to fit in memory.

The 100 MB threshold and the cache live behind **Settings → Performance**:
- *Use indexed mode for large files* — toggle off to force the old in-memory path for everything.
- *Threshold* — adjust the cutoff (10 MB to 10 GB).
- *Index cache* — view current cache size and clear it. Cache files live in `~/Library/Caches/com.traceview.app/indexes/`; macOS also evicts them automatically under disk pressure.

Supported formats: PlainText (BSD-syslog, dated-syslog), SCCM (CMTrace), CSV. IPS crash reports, `.diag` reports, Unified Log JSON, and gzipped files fall back to the in-memory path regardless of size.

## Performance targets

| Scenario | Target |
|----------|--------|
| Open 100K-line file | < 2s to first render |
| Scroll 100K lines | 60 fps |
| Live tail at 100 lines/sec | Smooth, no lag |
| Filter 100K lines | < 500ms |
| Memory (100K loaded) | < 150 MB |
| Open multi-GB file (indexed) | < 3s to first render |
| Open 5 GB indexed (cached) | < 500 ms |
| Scroll 36 M rows | 60 fps |
| Memory (indexed mode) | index + LRU only; file stays `mmap`'d |

## Status

**v1.1.1** adds in-app auto-update via [Sparkle](https://sparkle-project.org/). TraceView checks for new versions on launch and every 24 hours, downloads + verifies (Developer ID + EdDSA) updates in the background, and applies them after a confirm-and-relaunch prompt. Toggle in Settings → Updates.

**v1.1.0** landed the large-file engine: a custom virtual-scroll renderer that replaces the SwiftUI list, plus a memory-mapped *indexed mode* that auto-engages for files ≥ 100 MB, alongside an expanded 13-domain error-code database. Phase 1 of the Console Dense redesign is shipped; Phase 2 (Clean Native / Observability / Editorial as selectable theme skins) remains queued.

## License

[MIT](LICENSE) — use it, fork it, ship it. Attribution appreciated but not required.

## Support

TraceView is free and open source. If it saved you an hour of log-staring, you can [buy me a coffee](https://buymeacoffee.com/thefinder808) — zero pressure, always welcome.
