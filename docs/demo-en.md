# MuM

**Reading is the point, not a preview.**

## Why it's fast

| | MuM |
| :--- | ---: |
| Cold start to first window | ~0.3 s |
| First screen of a 5 MB doc | 302 ms |
| Installer | 1.7 MB |

## Typesetting, metered

Line height, tracking, the measure — **not defaults, measured**.
Latin text sits on an 80-character ruler; CJK keeps its own rhythm,
and mixed lines get the gap between 中文 and Latin exactly right.

> Most Markdown tools treat reading as a byproduct of editing.
> The word `preview` is itself the evidence.
>
> Projects answer "**where was I**", not "what is this".

## Code

```swift
let engine = MarkdownRenderer(theme: .paper)
let attributed = engine.render(markdown)
```

- Remembers where you stopped — across files, across launches
- ⌘F find · ⌘⇧O outline · ⌘⇧F cross-project search
- ⌘⇧E exports this page as an image
