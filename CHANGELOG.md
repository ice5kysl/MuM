# Changelog

[中文](CHANGELOG_ZH.md) · [Download for macOS](https://github.com/ice5kysl/MuM/releases/download/v0.8.0/MuM-0.8.0.dmg) · [Homepage](https://mum.jiker.ai)

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versioning follows [Semantic Versioning](https://semver.org/).

The single source of truth for the version number is [`VERSION`](VERSION) at the repo
root — the build script `scripts/build-app.sh` writes it into `Info.plist` as
`CFBundleShortVersionString` at packaging time, and converts it into a monotonically
increasing `CFBundleVersion`. **Maintained in exactly one place.**

Two conventions differ — don't mix them up:

| | Format | Why |
| :--- | :--- | :--- |
| `VERSION` file / `CFBundleShortVersionString` | `0.3.0` | Apple rejects a prefix |
| git tag / Release | `v0.3.0` | Convention, with `v` |

## [0.8.0] - 2026-09-28

**Usable by people who don't read Chinese.**

### Added

- **English UI** — all UI copy extracted (**249 entries / 250 table items**); menus,
  settings, About, the shortcuts panel, the feedback panel, and the outline sidebar are
  all bilingual. The mechanism is deliberately small: **the Chinese original is the key**,
  `en.strings` only stores the "Chinese → English" mapping, and a missing lookup falls
  back to Chinese and is recorded in `missingKeys` (the data source for residual-Chinese
  checks). No i18n framework — one table plus a two-level fallback is the whole thing
- **Language setting** — Follow System / 中文 / English; defaults to Follow System, and
  **switching takes effect immediately** (menus and static in-window copy are re-attached
  on notification, no restart needed)
- **In-app feedback channel** — Help menu "Send Feedback…" now prefers **sending directly
  from the app**: the panel states up front that "MuM version / macOS version / chip are
  attached, nothing else identifying", with GitHub as the fallback on failure or offline.
  It goes through msg9's relay (`in.msg9.io/f/mum`) with **zero keys on the client** —
  zero leak surface
- **English-primary README** — `README.md` switched to English; Chinese moved to
  `README_ZH.md`, with cross-links on both sides

### Changed

- **Latin typography tuned as its own pass** — English line spacing (≈1.46×), letter
  spacing, and measure width (550pt ≈ 80 characters) re-measured for the Latin writing
  system; **CJK paragraphs keep every existing attribute** (any paragraph containing a
  CJK character uses the original parameters)
- **One performance figure** — "cold start to window on screen" used to have four
  different numbers (260 / 229–248 / 280 / 250) across six files. The definition and
  number now live **only in [`docs/perf/ttfr.md`](docs/perf/ttfr.md)**; externally it's
  always "about 0.3 s". `measure-ttfr.sh` gained `CONFIG=release` (numbers must be
  measured on the build users actually get)

### Fixed

- **"Half Chinese, half English"** — views built before the language took effect had
  their copy frozen at build time, while switching languages only rebuilt the menu bar,
  so the sidebar / status bar / panels stayed in the old language. Static in-window copy
  now re-attaches on the language notification
- **Residual Chinese in EN mode** — new uitest scenario `english`: in EN mode it
  recursively walks the main window, both settings panels, About, the shortcuts panel,
  feedback, and the outline sidebar, asserting **zero CJK characters** and zero
  `missingKeys` misses. It caught two on day one (find bar, reader placeholder page —
  both hardcoded at build time)

### Tests

- Unit tests **147** (+30) · render self-checks 24 · **UI scenarios 14** (+1: `english`)
- **Zero Chinese regression as a byte-exact baseline**: the v0.7.9 and 0.8.0 Chinese
  snapshots are `cmp`-identical (light and dark sets)
- Feedback privacy: structural whitelist assertions (payload top-level keys are exactly
  `{text, contact, meta}`, `meta` is exactly `{version, os, arch}`) plus a live canary
  audit

## [0.7.9] - 2026-09-27

**The outline sidebar, polished against real use.**

### Changed

- **Outline sidebar (new in 0.7.8) smoothed out from real-device feedback** — a
  post-release round of fixes, all "awkward in use" items:
  - **Menu item moved from Edit to View** (alongside the project list / directory tree),
    with a checkmark state added — nobody could find it under Edit
  - **Draggable width** (160–420pt, remembered in `MuM.tocWidth`)
  - **Removed the duplicated heading**: the only H1 is the document title, not an outline
    entry (the filename is already in the title band); the "Outline" heading text removed
    too
  - **Top edge follows the splitView** (dynamic title-band height), fixing the overlap
    with the Export button
  - **The collapse entry went through three designs**: a floating "›" left of the divider
    → a thin strip at the bottom of the bar → **a thin strip at the bar header**. The
    first two failed on "awkward position, wastes a row at the top" and "too far from the
    hand"; the final one is a header strip: light gray background with a hairline at the
    bottom edge, clickable across its full width, and once collapsed to a sliver, "‹"
    pulls it back
  - **Inline disclosure triangles moved from before the text to the end of the row** —
    they no longer fight the indentation alignment, and truncated long titles yield space
    to them

### Fixed

- **The `--uitest` popovers scenario drifted red/green over long runs** — a transient
  popover closes itself when the window loses focus, so "click Aa again to collapse"
  walked into the reopen branch: **the same code could settle into stable red or stable
  green across six runs**. Not a product bug (cc proved it's environmental drift with a
  discrimination experiment: same anchor, green in the morning, red in the afternoon),
  but **an untrustworthy test is worse than a red one** — it trains the "red? just
  re-run" habit. Fix: pin the active state and drain the runloop before the second click,
  so `isShown` reads a settled value. Three consecutive runs + all scenarios green

## [0.7.8] - 2026-09-25

**Preview and source point at the same place.**

### Changed

- **Scroll sync is now content-aligned** — it used to be proportional (scroll position ÷
  total scrollable height), which assumes the two panes' height distributions are
  proportional; tables and code blocks render far taller than their source text, so the
  drift accumulates with document structure (on a heterogeneous sample: editor at 25%,
  preview already at +31%). Now the renderer records "source line → rendered position"
  anchors along the way (per block + per line within paragraphs), and editor scrolling
  maps the line at the top of the viewport to the same content in the preview. Sampling
  verdict: misalignment ≈0 at i=5/10/15 (threshold ≤2% of total length); uniform
  documents stay ≈0 with no regression. The drift-sampling test was promoted from
  "print-only" to a regression anchor. During progressive rendering, regions not yet
  covered by the mapping fall back to proportional without blocking the main thread

### Added

- **Outline sidebar (persistent right-side ToC, collapsible)** — toggle via "View →
  Outline Sidebar" or ⌘⇧O, state remembered across windows. Multi-level headings with
  disclosure triangles, click to jump, and "where you are" follows scrolling to highlight
  the current section. A small handle on the bar collapses it to a thin rail you click to
  reopen; close it with × and reopen from the menu or shortcut. The old ⌘⇧O popover
  outline is removed — the bar is the only outline (ice 2026-09-25). Write mode
  auto-collapses it; it comes back in Read/Preview
- **End-of-document marker** — in a long document scrolled to the bottom, you couldn't
  tell "finished reading" from "still loading". Now the bottom shows "Loading…" during
  progressive fill, replaced by a faint letterpress "── E N D ──" once the full document
  is in place. It's a view overlaid on the bottom padding band, not text: it doesn't
  participate in copy, export, or find (ice 2026-09-25)
- **Progressive fill speeds up when you're waiting on it** — when scrolling approaches
  the rendered end, the fill slice's time budget rises from 40ms to 150ms: you're staring
  at the bottom waiting, so input yields and catching up takes priority
- **Context menu "Copy Path"** — full path of a file or folder into the clipboard in one
  click, next to "Open in Terminal" (ice 2026-09-25)

### Changed

- **Soft line breaks render as real line breaks, matching GitHub** — a plain newline
  without trailing double spaces (a soft break) used to render as a space, so
  quote-block bullets written line by line and CJK documents with one sentence per line
  all ran together into a blob. GFM authors expect line-per-line display; now consistent
  with GitHub (ice ran into this on a quote block, 2026-09-25)

### Fixed

- **YAML frontmatter hidden while reading** — the metadata header wrapped in `---`
  (common in skill definitions and static-site posts) used to render as body content: the
  opening `---` became a horizontal rule and all field names leaked. Now reading /
  preview / export all strip it (same as Typora/Obsidian); Write mode always shows the
  raw text. Detail that comes with it: scroll-sync anchor line numbers have the strip
  offset added back, so alignment doesn't shift
- **Preview landing in bottom whitespace after switching files** — opening a new file
  that had never been read kept the previous document's absolute scroll offset: scroll a
  long document near its end, open a short one, and the viewport lands beyond the
  content, requiring a long scroll up to see text. Files without a saved position now
  start at the top (ice hit this in real use, 2026-09-25)
- **Prompt ordering in the update flow** — when 0.7.7 made `NSWorkspace.open` async it
  missed one semantic: the "disk image opened, drag MuM into Applications" prompt popped
  up before mounting finished, so clicking "Quit MuM" to look for the image could come up
  empty. The prompt now waits until the mount actually completes (a regression introduced
  in 0.7.7, fixed in this release)
- **Three window backgrounds — About / shortcuts / update banner — follow light/dark
  switching** — the backgrounds were stored as one-shot CGColor snapshots; after the
  window was reused from cache, switching appearance gave old background with new text
  (0.7.6 review F1). Unified onto `PaneBackgroundView` (`updateLayer` re-resolves against
  the current appearance every time). Pixel-verified: light snapshot background #F7F8FA,
  dark #17181C — no longer identical

## [0.7.7] - 2026-09-24

**No more spinning.**

### Fixed

- **Occasional permanent beachball (hang)** — in-app actions like "Open with X" and
  "Reveal in Finder" were waiting **synchronously on the main thread** for a
  LaunchServices XPC transaction (`xpc_connection_send_message_with_reply_sync`). If the
  transaction never comes back, the main thread waits forever and the UI beachballs
  permanently — ice hit this on a real machine multiple times. The captured scene: two
  `sample`s five minutes apart, 100% of samples on the same stack, while `lsd` was idle —
  **the transaction was wedged, not slow**.

  **13 call sites** of the same kind (8 `open` + 5 `activateFileViewerSelecting`), not
  just the onboarding page. All consolidated into the new `Core/ExternalOpener.swift`:
  opening uses the async overload `open(_:configuration:completionHandler:)`; Finder
  reveal has no async overload and moved to a background queue.

  **Why the old way was wrong**: the synchronous API is the cheapest to write, and the
  price is wiring the system's temperament straight into your main thread — one stuck XPC
  is one permanent freeze. These "looks like just one call" APIs deserve the most
  suspicion.

  A release gate was added too: `scripts/doc-check.sh` now checks whether `Sources/`
  contains synchronous calls bypassing the consolidation (negatively verified: plant one
  → red light), blocking a 14th site.

## [0.7.6] - 2026-09-23

**A new face.**

### Changed

- **New icon** — ice's hand-drawn version: a hand-drawn M plus a green quick stroke (with
  an arrow tail), in light and dark variants. The app icon uses the dark version (the
  source image has no alpha; at build time transparent corners are cut out via
  corner-connected regions before generating the iconset — the code-drawn
  `make-icon.swift` version retired); the landing page nav SVG icon replaced with the
  real image, following the page theme; apple-touch-icon synced
- **Icon source image compressed** — the 2048px master quantized to 256 colors: 2.9MB →
  55KB; the installer (DMG) accordingly 1.7MB → 1.6MB

### Fixed

- **About window** — removed the line "Reading is the point, not a byproduct of editing",
  which duplicated the positioning statement

## [0.7.5] - 2026-09-22

**Lone files open gently; deep directories jump into the terminal in one click.**

### Added

- **Open in Terminal** — available in both the file tree's ··· menu and the context menu,
  next to "Reveal in Finder". Brand-agnostic: it detects what you have installed in the
  order Ghostty → iTerm → system Terminal, and the menu name follows the machine; the
  system Terminal is always there, never a dead end. If the right-clicked item is a file,
  it opens the folder containing it

### Changed

- **A lone file no longer opens its folder as a project** — opening a file that belongs
  to no project from outside (Finder double-click / drag-in / `open`) enters single-file
  mode: both sidebars collapse, the content area reads directly, and the file tree isn't
  stuffed with an entire irrelevant folder. Opening or switching back to a project
  restores both sidebars. If the file belongs to an already-open project, behavior is
  unchanged: switch to it. In single-file mode ⌘N creates the new file next to the
  current one (the project sidebar is collapsed — creating into an invisible project
  would lose it); the save panel only appears when no file is open

### Fixed

- **MuM actually shows up in Finder's "Open With"** — 0.7.4 claimed to register
  extensions like srt/log/csv, but in practice it didn't work: LaunchServices ignores
  CFBundleTypeExtensions when it sees LSItemContentTypes in the same document type group,
  so the extensions never entered the bindings. Splitting into an extension-only
  "subtitles & plain text" group made registration real (verified via dump)

## [0.7.4] - 2026-09-22

**Updates come to you; subtitles read directly.**

### Added

- **Update banner with one-click download** — when a new version is found, no more
  hunting for the installer on the Release page: "Download Update" downloads the DMG
  inside the app (with progress percentage), auto-mounts the disk image when done, and
  the last step is dragging MuM into "Applications" to replace it. Falls back to jumping
  to the page when there's no direct link; the download remains an anonymous request with
  no user identifiers
- **Subtitle files open as text** — srt / ass / ssa / vtt (plain text with timelines;
  GBK encodings are backed by TextDecoding's round-trip validation); these extensions are
  also registered in Finder's "Open With" (along with log / csv / tsv / vcf / ics), so
  MuM is directly selectable from the context menu

## [0.7.3] - 2026-09-21

**HTML inside Markdown behaves; PDF export honors page breaks.**

### Added

- **.html goes to the "unsupported format" guidance page** — readers of .html files
  (print exports, web archives) want the rendered page; MuM has no web engine and doesn't
  chase browsers. Opening one now offers "Open in Safari / Reveal in Finder" directly
  instead of showing source. vue / svelte are component source and still open as code
  with highlighting
- **Inline HTML rendered from a whitelist** — common inline tags like `<small>` `<mark>`
  `<sup>` `<sub>` `<u>` `<b>/<i>/<s>` `<kbd>` `<br>` are typeset by semantics (smaller,
  highlight, super/subscript, underline…), and the tags themselves no longer show as
  monospaced source; semantic-free tags like `<span>` are swallowed without style
  changes; block-level HTML comments and page-break empty divs — pure layout directives —
  are hidden as whole blocks. HTML fragments outside the whitelist or carrying real
  content still render as raw text, so pasting fragments into notes is unaffected

### Fixed

- **Exported PDFs actually break at page-break directives** — print-oriented documents
  often mark break points with
  `<div style="break-after: page; page-break-after: always;"></div>`; these directives
  are hidden while reading, and now PDF export (⌘⇧E and CLI `render --pdf` alike) forces
  a page break at those positions — the author's page count is the page count. PNG long
  images have no concept of pages and are unaffected
- **PDF / images / unsupported formats could open to a blank page** — these files have no
  source to write, but the Write/Preview segments were still clickable (shortcuts ⌥⌘1/3
  could switch too), landing on an empty, non-editable editing area. Now non-text files
  keep only Read enabled, the rest grayed out; with no document, all three segments are
  gray

## [0.7.2] - 2026-09-20

**File formats: read well what we can, give directions for what we can't.**

### Added

- **Unsupported formats get directions** — opening Word / Excel / PPT / archives /
  audio-video formats we don't plan to support shows a placeholder page stating "MuM is a
  Markdown reader" with two destinations: "Open with (the system default app)" (Enter to
  go) and "Reveal in Finder"
- **RTF rendered as rich text** (read-only) — previously opened as plain text, a screen
  full of control words; NSAttributedString supports it natively, zero dependencies added
- **CSV / TSV rendered as tables** — RFC 4180 parsing (quotes, escapes, in-field
  newlines, CRLF all handled), converted to Markdown tables running through the same
  hand-tuned typesetting; editing still works on the raw text. Single-column or over
  5000 rows falls back to plain text
- **ipynb opens as JSON source** (with highlighting); vcf / ics recognized as plain text

## [0.7.1] - 2026-09-19

### Fixed

- **Scrolling jank** — **this is the debt owed since v0.5.1**.
  `drawCodeBlockBackgrounds` did an `Array(entireText.utf16)` on every draw — **copying
  the whole document**. `sample` measured it at **~40%** of the main thread. Changed to
  direct index-based reads:

  | Scenario | P95 before | P95 after | Effective fps |
  | :--- | ---: | ---: | :--- |
  | 1 MB first scroll | 28.5 ms | **7.2 ms** | 56 → **119 fps** |
  | 5 MB first scroll | 117 ms | **7.7 ms** | **17 → 100+ fps** |

  **17 fps at 5 MB — that's an unusable state**, and it had been sitting there since
  0.3. This matters beyond the fix itself: **it's the first fix the "reading-first"
  positioning was forced into by its own metrics**.

### Added

- **Version update check** — silently queries GitHub Releases after launch (anonymous
  GET); a new version only produces a **non-focus-stealing** banner (with "View" and
  "Ignore This Version"); Help menu gains "Check for Updates…"
- **In-app feedback entry** — Help menu "Send Feedback…" plus a link row in the About
  window, going straight to the issue template with **MuM version / macOS / chip
  pre-filled**

### Added

- **Version update check** — one silent check of GitHub Releases after launch (anonymous
  GET, no identifiers of any kind); a new version only shows a non-focus-stealing banner
  at the top of the window: "View Update" jumps to the Release page, "Ignore This
  Version" remembers and stops nagging. Help menu gains "Check for Updates…" for manual
  triggering, and it says so plainly when you're already on the latest
- **Feedback auto-carries versions** — Help → Send Feedback… goes straight to the
  feedback template with MuM version / macOS version / chip pre-filled into the form, no
  typing

### Fixed

- **Large-document scrolling jank** (v0.5.1 debt, measurement-driven) — the code-block
  background drawing path had an `Array(entireText.utf16)`: every code block, every draw,
  copied the entire document; scrolling a 5MB document burned ~40% of the main thread on
  this copy (`sample`-measured). After switching to direct index-based reads: 1MB first
  scroll P95 28.5→7.2ms (real on-screen 56→119fps), 5MB first scroll P95 117→7.7ms (real
  on-screen 17→100+fps) — both back within the v0.5.1 verdict line (P95 ≤16.7ms / worst
  ≤33ms, release build, n=3 each)

## [0.7.0] - 2026-09-19

**Jot it down — file management entered the file tree, and the toolbar became what it
should be.**

Every item in this release comes from ice's real-use feedback: quick capture, renaming,
deletion, a breathing toolbar. All "you only know once you've used it" things.

### Added

- **⌘N quick new file** — with a project open it's created in the selected directory
  (incremental naming, never overwrites), opens straight into Write mode with the cursor
  in place — just write; without a project it goes through the save panel
- **File tree context menu** — New File / New Folder / Rename… / Reveal in Finder / Move
  to Trash; hovering any row also reveals a ··· entry at the row's end
- **Inline rename** (files and folders) — Finder-style in-place editing, Enter to
  confirm, Esc to cancel; the path of an open file follows the rename, so ⌘S won't write
  a ghost copy at the old path
- **Move to Trash** — recoverable deletion without jumping to Finder
- **··· export menu** (top-right of the content area) — PNG / PDF in one click, no
  shortcuts to memorize

### Improved

- **Three-segment toolbar** — Write/Read/Preview moved to horizontal center (the mode is
  the document's primary viewpoint switch), document title enlarged to 16pt, toolbar
  made taller
- **New icon composition** — the M and green underline centered as a whole
  (pixel-verified)
- **About window catches up with the new positioning** — "A fast, native Markdown engine
  — for humans and agents", with the name explained: MuM = Multi-project Markdown
- **Landing page** — real product screenshots (light/dark follows the system), measured
  numbers, copy polished over three rounds

### Fixed

- Files under symlinked paths (/tmp etc.) couldn't be selected in the file tree —
  `resolvingSymlinksInPath` doesn't resolve `/var` on this generation of macOS; both
  sides of the path comparison now go through `realpath(3)`
- The ··· button didn't respond to clicks — an `NSButton` with a menu attached doesn't
  pop up automatically; you have to wire an action and call `popUp` manually

## [0.6.0] - 2026-09-19

**Handable to someone else — for the first time, a second person can install it
themselves.**

Before this we made five versions and no second person ever used it. What this release
adds is that "half level" of maturity: deliverability.

### Added

- **Export (⌘⇧E)** — save the current document as an image / PDF using the current
  reading theme, width, and font size — **what you see is what you get**. No format
  pickers, margins, or headers/footers — it's "take away exactly what you're looking at",
  not a typesetting tool
- **Headless CLI (for agents)** — `mum render / outline / search / check`, all with
  `--json` + meaningful exit codes + **no window** (`activationPolicy(.prohibited)`).
  Shares **the same body-rendering entry point** as export
- **Landing page mum.jiker.ai** — bilingual Chinese/English, single static file, no
  tracking scripts

### Engineering

- **Signing + notarization in the regular build** — company Developer ID certificate +
  `notarytool`, the full pipeline verified end to end. Signing identities read from the
  environment (`MUM_SIGN_IDENTITY` / `MUM_NOTARY_PROFILE`), **never committed**
- **Repo went public** — full-history scan for sensitive data (gitleaks over 117 commits,
  no leaks + targeted scan, zero hits), and the signing identity scrubbed from **all of
  history** before force-pushing
- **CI automation** — GitHub Actions is free for public repos (including macOS runners);
  the cost concern that originally forced manual triggering is gone
- `--uitest` — in-app self-driven UI testing, **zero permissions**, deterministic waits,
  CI-ready. 7 scenarios / 58 steps all green, **negative verification precise to the
  step** (deliberately break one thing, and the test must fail)
- Three hard rules written into `docs/collaboration.md`: **no `git add -A`** (three
  agents share one working directory), **clean up whatever you use**, **file ownership by
  directory**

### Missed targets (recorded honestly)

- **TTFR cold-open @1MB: target ≤600 ms, measured median 622 ms.** The target doesn't
  move; the chase continues
- **v0.5.1's scroll frame rate was never measured** — the definition was written, the
  tool shipped (`--bench scroll`), cc ruled on the dual criteria, but **the measurement
  itself was missed**. Recorded here; we don't pretend it was done

## [0.5.0] - 2026-09-18

"Findable" — actually standing up the "multi-project" pillar.

### Added

- **Global search (⌘⇧F)** — search filenames + full text across all open projects, with
  **results streaming in**. Measured: first result **26.5–29.9 ms** (target ≤300), full
  scan complete in **1.4 s** (target ≤5 s)
- **Click a result and read that line directly** — opens the file positioned at the hit,
  reusing the find highlight. The end of a search isn't "a file list"; it's "I'm already
  reading that passage"
- **Search scope visible + shrinkable** — you can see which projects are being searched
  and exclude one with a click

### Fixed

- **R-5 double ⌘F** (user-reachable) — the system find bar removed; everything goes
  through the custom find bar
- Audit cleanup of existing code: 13 dead-code sites (each grep-verified to have zero
  references before deletion), magic numbers consolidated

### Engineering

- **Signed release script** — company Developer ID certificate + `NOTARYPROFILE`
  notarization, **full pipeline verified end to end**
- **Selected-text context menu**: Copy + two levels of find
- **Preview links open internally** + **reading history back / forward**
- Icon aligned with Vme: darker background, thicker green line
- Search completeness criteria: **enumerable** (filenames) = all results arrived;
  **streaming** (full text) = first result arrived — note: filename search is currently
  **streaming** (first result 62ms, the last waits for enumeration to finish); "get all
  from the in-memory file tree" is not yet implemented, left for a later release

### Added

- **Global search (`⌘⇧F`, v0.5 "Findable")** — search filenames + full text across all
  open projects, results streaming in (no waiting for the scan to finish); click a result
  to open the file positioned at the hit (reusing the preview find highlight); search
  scope visible and shrinkable (exclude a project from the panel in one click). **No
  index, search on demand** — zero resident cost, cold start untouched. Files over 10MB
  are explicitly reported as "skipped"; excessive hits are explicitly truncated — nothing
  silently dropped
- **About window** — a custom 300pt small window (icon / version / one-line positioning /
  link row), links underline on hover, Esc closes. Not the system standard about panel:
  its credits text area has uncontrollable width, copy wraps at the mercy of fate — two
  different design systems from MuM's
- **Keyboard shortcuts window** (Help → MuM Guide) — replaces the NSAlert wall of plain
  text: right-aligned keys in one column, descriptions in another, five groups with
  breathing rhythm; fixed-height content, Esc closes
- **Document links in preview open directly** — relative links (like
  `[VISION.md](VISION.md)`) open the corresponding file inside MuM instead of being
  handed to the system. Root cause: `textView.delegate` was never wired — `clickedOnLink`
  was written but never called
- **Reading history back/forward (`⌘[` / `⌘]`)** — link jumps, file-tree clicks, and
  search results all live on one history line; returning to the previous document brings
  back the reading position too (reusing reading-position memory). No tabs: tabs are an
  interface for "comparing multiple documents" and overlap with the file tree's job
- **Context actions for selected text** — beyond Copy / Select All, a selected word can
  go straight to "Find in Document" or "Search in All Projects" (the selection pre-fills
  the corresponding find; global search starts immediately). Multi-line selections
  collapse to one line; the menu title truncates but the query stays intact

### Engineering

- `scripts/make-bench-fixture.py` gains a `corpus` mode: generates a multi-project search
  benchmark corpus with 5% of files carrying a rare word, directly comparable against
  `grep -r`
- Unit tests 49 → 60 (11 in `GlobalSearchEngineTests`: binary penetration, GBK, symlink
  loops, deterministic cancellation, truncation, etc.)

## [0.4.1] - 2026-09-18

### Fixed

- **Window couldn't be resized by dragging** (introduced by dsh) — to keep the window
  from collapsing, `widthAnchor == 1440 @.defaultHigh` was added, with a comment
  asserting "this yields when the user drags". **That assumption was wrong**: a
  750-priority equality is still preferentially satisfied by the solver, and AppKit
  pulled the window back to 1440×900 every display cycle. Changed to a minimum
  constraint; the initial size is set explicitly once by `showWindow`
- **R-1 nested-list paragraph styles overridden** — `renderListItem` applied paragraph
  style across the whole item range, clobbering the styles of nested items / code blocks
  / tables. Changed to only fill ranges without a style
- **E-2 opening into a non-active project paid for an extra old-file open** — that
  session restore is now skipped

### Engineering

- `accept.sh` cleanup gains `lsregister` unregistration — prevents recurrence of E-1
  (ghost instances) at the root cause
- R-1 gained 5 regression anchors (failing pre-fix / all green post-fix, verified both
  directions)
- Unit tests 44 → 49

### Verification

cc measured the window size with **CGWindowList** (fresh install 1440×900 / size
restoration), **verifying the automatable parts without a mouse**; real dragging still
awaits human confirmation.

### Fixed

- **Nested-list level indentation clobbered by the outer list item (audit R-1)** — at the
  end of `renderListItem`, paragraph style was applied across **the whole item range**,
  so nested list items' hanging indents and the paragraph styles of code blocks and
  tables were all overridden; nested lists visually degenerated to one level. Changed to
  **only fill ranges that don't yet have a paragraph style** (isomorphic to how
  `renderBlockQuote` fills quote depth): simple lists look unchanged — the marker sits at
  the paragraph start, and TextKit paragraph layout takes the first character's paragraph
  style, so the marker's list style already applies; continuation paragraphs of
  multi-paragraph items get the list style filled in and keep their indent; nested-block
  styles are never clobbered again.
- **Opening a file in a "non-active project" paid for an extra old-file open (E-2)** —
  when double-clicking / `open -a` a file belonging to another project, the
  project-switch notification first fully opened that project's **last file** (read +
  render + close), then opened the actually requested one; with unsaved changes it also
  popped an extra confirmation. 0.4.0's "external requests skip restore" only covered the
  launch path; now the warm-open path is covered too: a suppress flag is set before
  switching, and the notification handler skips restore for exactly that one time.
  Measured: the open chain's readText dropped from two calls to one.

## [0.4.0] - 2026-09-18

Made "fast" true again, and filled in the ways to open things. **Plus all four
high-severity findings from cc's full audit closed.**

### Added

- **Progressive rendering** — the first screen renders and shows first, the rest is
  appended in slices. **TTFR cold-open for a 1MB document dropped from 6800ms to
  609–634ms** (median 622ms, n=3, reproducible in an isolated worktree)
- **`mum .` CLI** — open the current directory from the terminal
- **⌘P Quick Open** — fuzzy file search within a project
- **Drag to open** — drag files / folders onto the window or the Dock icon
- **Window to the front** — after `open`, the window is guaranteed to be frontmost

### Fixed (the four high-severity findings of the full audit, all independently verified
by cc)

- **D-1 quitting loses unsaved edits** — ⌘Q and the red light / ⌘W: six exit paths now
  converge on one confirmation entry
- **D-2 non-text guard penetrated by binaries** — `svgz` / `plist` / `lock` types could
  previously be corrupted; decoding and saving now go through the same path
- **C-1 `FileWatcher` stop-path use-after-free** — `passUnretained` replaced with
  `CallbackBox`; all stop actions moved into the serial queue
- **R-2 `drawDecorations` nullified non-contiguous layout** — **this is the real culprit
  behind "5MB janks for 9 seconds"**. Post-fix 5MB first-screen layout is **301.6ms**
  (the full-layout upper bound of 11.5s is unchanged, a ~38× gap) — **the symptom is
  eliminated, not the number moved**
- **Full-document layout on the typing hot path** — `show()` relayout no longer computes
  document height (1MB: 812ms per keystroke → ~0.1ms); dsh broke this in 0.3 while doing
  reading position
- `.mumenv` failing on a fresh clone because `GITHUB_PROXY` is undefined (unavoidable in
  open-source scenarios)
- Two empty-state layout bugs: running to the bottom-left corner with text clipped; two
  layers of empty states stacked on display

### Engineering

- **`scripts/accept.sh`** — runs acceptance on a clean worktree (build / self-check /
  unit tests / packaging), cleans itself up afterward
- **`scripts/measure-ttfr.sh`** — reproducible measurement for TTFR verdict data,
  outputting median / standard deviation / range
- **`scripts/make-bench-fixture.py`** — benchmark samples are now rebuildable instead of
  keeping large files around
- **`docs/status.md`** — project status board
- Unit tests **0 → 44**
- `docs/` holds all documentation; the root keeps only `README` / `CHANGELOG` /
  `LICENSE` / `VERSION`

### Missed targets (recorded honestly)

- **TTFR cold-open target ≤ 600ms, measured median 622ms.** The gap is within measurement
  noise, **but the target doesn't move** — recorded in `docs/status.md` and
  `docs/metrics.md`; v0.5 keeps chasing it

### Fixed

- **The real main cause of slow large-document opening** — opening a 1MB markdown took
  5.2 seconds to put anything on screen, ≈4.9 of which was **the editor `setText`'s full
  contiguous layout** (the editor is invisible in Read mode, yet it still laid out all
  650K characters). Enabled `allowsNonContiguousLayout` for the editor too (the preview
  area had it since 0.3); the synchronous segment of opening (applyWorkspace) went
  **4.97 s → 73 ms**, and 1MB opening meets the bar (≤400 ms). **Why the old diagnosis
  was wrong**: 0.3 had misidentified the main cause as "rendering" — preview rendering is
  async and isn't on the synchronous open path at all; only the preview got
  non-contiguous layout back then, the editor didn't. Measurement method in the next
  item.
- **Whole-document layout during typing relayout** — another call site of the same root
  cause (forced full layout) as slow opening: position-preserving relayout used to go
  `scrollFraction()` → `documentHeight` → `ensureLayout` over the whole document, so
  every keystroke in a 1MB document (after the 110ms debounce) triggered a full layout
  (measured ≈812 ms) — typing in large documents was unusable. Relayout only needs
  "don't jump": changed to remember the absolute scroll position (`bounds.origin`,
  cheap); the fraction is only used across opens (the document may have grown or shrunk).
  Other call sites of the same root cause handled too: editor scroll sync and saved
  reading position use the **cached** `documentHeight` (no re-layout when content is
  unchanged; invalidated on content/width changes).
- **Progressive rendering for large documents** — opening markdown over 100K characters,
  the first 80 top-level blocks go on screen first (the R in TTFR), and the rest is
  filled in ≤40ms slices: scrolling stays usable during the fill, and already-shown
  content doesn't shift (appends only happen at the document tail). Timing changed,
  content untouched — the stitched result is byte-identical to a full render
  (`ProgressiveRenderTests` swept cut points × budgets). With a saved reading position
  it's progressive too: the first screen arrives, and the position is restored after the
  full document is in place (if the user scrolled during the fill, the user wins). 1MB
  TTFR measured **489–561 ms** (two rounds), full fill ≈1.3 s. **Rollback switch**:
  `defaults write sh.ice.mum MuM.disableProgressiveRender -bool true`, one command back
  to synchronous rendering (the bench bundle domain is `sh.ice.mum.bench`).
- **Open-path scheduling** — three things interlocked: the window goes on screen first
  (content restore moved out of init; window on screen 330→250 ms and no longer varies
  with file size; external requests from double-click / drag-in take priority over last
  session's leftover files); open-path rendering changed to synchronous execution
  (rendering work items after the window was on screen got squeezed out by the first
  frame for 127 ms — synchronizing nets that back); `updateStatusBar` gained input
  fingerprint dedup + word count changed to a single-pass allocation-free scan (open path
  3×75 ms → 1×40 ms). 1MB TTFR two rounds **458/462 ms**, small-document cold start 266
  ms, no regression.
- **Quitting/closing the window loses unsaved edits (audit D-1)** — unsaved confirmation
  was only hooked on open / close / reload / mode-switch; ⌘Q and clicking the red light
  had **no guard at all**, and changes were simply lost. Now six paths (including
  `applicationShouldTerminate` and `windowShouldClose`) converge on one confirmation box.
- **Non-text files penetrating the guard into the editor (audit D-2/D-3/D-8/D-9)** — the
  old decode chain was "UTF-8 → system detection → Latin-1": Latin-1 "succeeds" on any
  bytes, so binaries (`svgz`/`plist`/`lock`) entered the editor as mojibake, and one more
  ⌘S destroyed the original file. New unified decode entry `TextDecoding`: NUL bytes are
  rejected outright; UTF-8 → GB18030 → Latin-1 tried in order, with UTF-8 and Latin-1
  results sniffed for control-character ratio (>1% rejected as binary), and GB18030
  requiring **round-trip validation** (only counts as a correct guess if it encodes back
  to the same bytes — system detection misjudges GBK as a single-byte encoding and
  produces mojibake). Both the open path and the "modified externally on disk" path go
  through it; unreadable files enter a safe empty state with a non-editable editor
  (typing into an empty editor and saving destroys the file all the same). The read
  encoding is remembered per file, and saving writes back **the same one** — no more
  silently converting GBK to UTF-8.
- **Two holes in save-conflict detection (audit D-4/D-5)** — external modification used
  to be judged by `mtime > time of read`: `git checkout` / `rsync -a` write mtimes back
  into the past and the check silently failed, changed to `!=`; when the on-disk mtime
  can't be read (file deleted/unreadable) it used to pass silently — now treated as a
  conflict too. Also the mtime baseline changed to **read after taking it** (the old
  order was reversed, so a modification mid-read escaped the net, D-6); atomic writes
  change the inode, so POSIX permissions are noted first and restored after writing
  (D-7).
- **FileWatcher stop-path use-after-free and race (audit C-1/C-2)** — the FSEvents
  context carried `passUnretained(self)`: there was no synchronization between
  `deinit → stop()` and in-flight callbacks on the serial queue, so a callback could
  dereference an already-freed self; the `pending` debounce items were read and written
  bare from both the main thread (stop) and the queue (scheduleFire). Changed to: the
  context carries a callback box strongly held by the stream's lifetime (weakly pointing
  back to self), and all stop actions execute via `sync` on the same serial queue —
  in-flight callbacks naturally drain before resources are released, and `pending` is
  only touched on the queue.
- **The real culprit behind 5MB documents janking for 9 seconds per draw (audit R-2)** —
  the preview area's `drawDecorations` took the glyphRange from **the whole document's
  `bounds`**: every draw forced a full layout of the entire text, and
  `allowsNonContiguousLayout` was completely nullified — the non-contiguous layout
  enabled in 0.3 never actually took effect. Changed to cover only `dirtyRect` (converted
  to container coordinates, ±24pt bleed to cover decoration lines). `--bench` gained a
  "first-screen layout" section measuring the real cost of the drawing path: the 5MB
  sample is **301ms vs 11.3 seconds** for full layout (the "layout" section measures the
  `ensureLayout` full upper bound, unchanged as expected). The same path also fixed
  `withoutTrailingNewlines`'s `Array(utf16)` full-text copy — O(entire text) per
  attribute run, O(runs × entire text) on large documents.

### Added

- **`mum` command-line entry** — `mum .` opens the current directory as a project, `mum
  file.md` opens a single file. The binary ships inside the bundle
  (`Contents/Resources/mum`), symlink it into PATH and go; goes through LaunchServices,
  no second process spawned
- **⌘P Quick Open** — fuzzy filename search within a project (subsequence matching +
  contiguity/word-boundary weighting), ↑↓ to select, ⏎ to open, Esc to close. The index
  builds in the background and caches per project; filtering 10K files is
  millisecond-level (`QuickOpenTests` has a timing assertion). The old ⌘P "Filter Files"
  stays in the menu but no longer owns the shortcut
- **Drag to open** — drag files/folders onto the window to open them (Dock drop already
  worked)
- **Window to the front after open** — when the app is already running, `open -a` /
  double-click / drag-in no longer opens the file into a window buried in the back

### Added (measurement tooling)

- **Segmented render timing** — new `RenderProfiler` (gated by `MUM_RENDER_TIMING=1`,
  zero cost normally); `--bench` now outputs render sub-segments: internal parsing /
  syntax highlighting / tables / inline parsing / other. The open path's `LaunchTimer`
  subdivides in sync (readText / setText / updateStatusBar / performRender / show).
  Measured: of the 1MB render's 611 ms, tables and inline each take about 40%, syntax
  highlighting only 4% (674 calls, 27 ms) — ruling out the "syntax highlighting is the
  bottleneck" guess

## [0.3.0] - 2026-09-18

0.3 is readable — completing the act of "reading".

### Added

- **Performance baseline** (0.3) — new `--bench <file.md>` with three timed segments:
  parse / render / layout. Measured 1MB total 1.54 s, 5MB total 11.6 s

### Known Issues

- **Slow large-document opening** — opening a 1MB markdown in the app takes 1.1 seconds
  (small files 280 ms); the main cause is **rendering**, not layout (measured: enabling
  non-contiguous layout didn't change open time). Not yet localized to a specific render
  segment; the next step is adding segmented timing to `render(_:)`
- Layout itself takes 9 seconds at 5MB. `allowsNonContiguousLayout` is enabled to improve
  scrolling, but layout cost on the open path is still there. Also measured: tables only
  account for 8% of it — the bottleneck is text volume
- **Document outline** (0.3) — ⌘⇧O pops up a heading list; click one to jump there. Made
  a popover instead of a persistent sidebar: an outline is a "once in a while in a long
  document" action, and a persistent one would permanently eat body width
- **⌘F find in the preview area** (0.3) — highlights all hits, marks the current one in
  orange; ⏎ / ⇧⏎ to jump, Esc to close. The find bar is a strip of the content area
  itself (not a separate floating layer) and doesn't cover the body
- **Reading position memory** (first item of 0.3 "readable") — remembers where you were
  when switching files or quitting, and returns there next time. Stores a 0…1 fraction
  instead of pixels: the position stays sensible after changing font size or letter
  spacing

## [0.2.0] - 2026-09-17

Settings gained real structure, typography was redone for Chinese, and two
data-destroying problems were fixed.

### Added

- **Two settings entries** — `Aa` (display settings: appearance, reading theme,
  typography, editor display) and `⚙` (system settings: launch, files, indentation,
  system integration). Mixing them lets "set once and forget" settings push
  "fine-tune repeatedly" settings out of sight
- **Reading themes** — Follow Appearance / Paper / Quiet / High Contrast. Only changes
  the paper color of the reading surface, orthogonal to the app appearance (you can have
  "light UI + warm paper"). Each theme ships its own syntax color set
- **Font family** (system / serif / mono), **letter spacing**, **typewriter mode**
- **Editor line numbers** — only paragraph first lines are numbered; soft-wrapped
  continuation lines are not
- **"Open with Default App"** — non-Markdown files show an icon in the toolbar that hands
  the rendered result to the system (HTML to the browser). Rendering HTML ourselves would
  either require a web engine or forever chase browsers, so we don't
- **Set as default Markdown editor** — via `NSWorkspace.setDefaultApplication`
  (macOS 12+)
- **Document type declarations** — an "Open With" candidate for Markdown / plain text /
  source code / folders

### Changed

- **Typography redone for Chinese** — line spacing 4pt → 7pt (1.47 → 1.73× line height),
  paragraph spacing 8 → 12pt, and vertical spacing for headings, lists, code blocks,
  rules, and tables loosened along with them. CJK glyphs fill the em box; Chinese set on
  Latin line spacing feels cramped
- **App icon redone** — the M changed to geometric drawing (mitered sharp corners →
  rounded vertices), the bottom stroke turned green; centering and overflow fixed
- Settings panels changed to two columns so everything fits on one screen

### Fixed

- **Non-text files are no longer editable or savable** — previously, opening an `.ipa`,
  typing, and hitting `⌘S` would write text into that binary file
- **Compare disk mtime before saving** — if the file was modified externally, ask first
  instead of silently overwriting
- **An extra relayout when switching to Read / Preview** — `performRender()` returned
  early in Write mode, so after switching modes you'd see **the previous file's**
  leftover content
- **Syntax highlight colors now come from the reading theme** — they used semantic colors
  resolved against the app appearance; with a dark app + "Paper" theme, the comment color
  resolved to light gray, illegible on cream paper
- **Panel / status bar backgrounds changed to `updateLayer()`** — no longer relying on
  the `viewDidChangeEffectiveAppearance` callback (which isn't guaranteed to reach every
  view)
- **Long status-bar paths no longer stretch into two lines** — attributed text overrides
  `NSTextField`'s own `lineBreakMode`, so it must be written into the attributed text
- The window could open buried behind other windows when opening a file

### Engineering

- **`VERSION` became the single source of truth for the version number** (SemVer),
  written into `Info.plist` at build time and converted into a monotonically increasing
  `CFBundleVersion`
- **This file (CHANGELOG)** along with [VISION.md](docs/vision.md) and
  [ROADMAP.md](docs/roadmap.md)
- **GitHub Actions** — build + 24 self-checks + packaging + off-screen snapshots.
  Currently manual-trigger only: macOS runners are billed for private repos, so automatic
  triggers would fail for sure
- **`.mumenv` dropped the `HOME` redirection** — it left git / gh / UserDefaults unable
  to find their configs and actually bit us three times (see README "About .mumenv")
- New icon measurement tooling under `scripts/`

## [0.1.0] - 2026-09-17

First usable version. Positioning: **Reading is the point, not a preview.**

### Added

- **Three-column layout** — project list / directory tree / content area. Columns 1 and 2
  are collapsible via two layout icons on the bottom bar's central axis (`⌘0` / `⌥⌘0`)
- **Multi-project** — open multiple project folders at once, switch instantly with
  `⌘1`…`⌘9`; drag in from Finder or `open -a MuM <path>` works too
- **Three presentation modes** — Write (source) / Read (rendered) / Preview (side by
  side), `⌥⌘1/2/3`. Switching files keeps the current mode instead of jumping back to
  Read every time
- **Native Markdown renderer** — cmark-gfm parsed into `NSAttributedString`, no web
  engine anywhere. Supports headings, paragraphs, GFM tables, task lists, (nestable)
  block quotes, code blocks and inline code, rules, and local images. Quote bars, rules,
  heading underlines, and code-block backgrounds are all hand-drawn
- **Syntax highlighting** — a data-driven single-pass scanner covering 40+ languages
- **Reading themes** — Follow Appearance / Paper / Quiet / High Contrast. Only affects
  the reading surface's paper color, orthogonal to the app appearance (you can have
  "light UI + warm paper"). Each theme ships its own syntax color set
- **Display settings (Aa)** — light/dark UI, reading theme, font size, font, line
  spacing, paragraph spacing, letter spacing, reading width; editor font size, line
  numbers, current-line highlight, typewriter mode
- **System settings (gear)** — restore files on launch, launch presentation mode, show
  hidden files, Tab indent width, default Markdown editor
- **Source editor** — all smart substitutions off, Tab inserts spaces, Enter continues
  list markers, line-number gutter, current-line highlight
- **Document type declarations** — declared as an "Open With" candidate for Markdown /
  plain text / source code / folders (`LSHandlerRank = Alternate`, doesn't steal the
  default), with one-click "set as default Markdown editor"
- **"Open with Default App"** — non-Markdown files show an icon in the toolbar that hands
  the rendered result to the system (HTML to the browser, SVG to Preview). Rendering HTML
  ourselves would either require a web engine or forever chase browsers, so we don't

### Engineering

- **`--selftest`** — 24 rendering assertions, headless, 0.03 seconds, CI-ready
- **`--snapshot`** — renders the entire window off-screen to a PNG; the UI can be
  inspected from a locked screen / SSH / CI
- **`MUM_LAUNCH_TIMING=1`** — prints per-stage launch timing (measured: process start →
  window on screen 280ms, of which rendering 0.03s)
- No `.xcodeproj` — the entire app is `Package.swift` + one `Info.plist`

### Fixed

- Fixed preview not relayouting when switching to Read / Preview — `performRender()`
  returned early in Write mode, so after switching modes you'd see **the previous
  file's** leftover content
- Fixed syntax highlighting using semantic colors, making comments illegible under the
  "Paper" theme — semantic colors resolve against the app appearance while the paper
  color is decided by the reading theme; the two must come from the same source
- Fixed panel / status bar backgrounds not refreshing on appearance changes — changed to
  `updateLayer()` re-resolving on every display, no longer relying on the
  `viewDidChangeEffectiveAppearance` callback (which isn't guaranteed to reach every
  view)
- Fixed long status-bar path labels stretching into two lines and overflowing the bar
  height — attributed text overrides `NSTextField`'s own `lineBreakMode`, so it must be
  written into the attributed text

### Security

- Non-text files (images / PDFs / binaries) can no longer be edited or saved —
  previously, opening an `.ipa`, typing, and hitting `⌘S` would write text into that
  binary file
- Disk mtime compared before saving; if the file was modified externally, ask first
  instead of silently overwriting

[Unreleased]: https://github.com/ice5kysl/MuM/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/ice5kysl/MuM/releases/tag/v0.6.0
[0.5.0]: https://github.com/ice5kysl/MuM/releases/tag/v0.5.0
[0.4.1]: https://github.com/ice5kysl/MuM/releases/tag/v0.4.1
[0.4.0]: https://github.com/ice5kysl/MuM/releases/tag/v0.4.0
[0.3.0]: https://github.com/ice5kysl/MuM/releases/tag/v0.3.0
[0.2.0]: https://github.com/ice5kysl/MuM/releases/tag/v0.2.0
[0.1.0]: https://github.com/ice5kysl/MuM/releases/tag/v0.1.0
