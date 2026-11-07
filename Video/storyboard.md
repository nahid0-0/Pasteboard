# Pasteboard — ad video storyboard

Target: ~35 seconds, 16:9 (re-cut to vertical later if needed). Captions on screen, no voiceover required.
Tagline: **"Your clipboard forgets. Pasteboard doesn't."**

## Before you film

1. `./Video/demo.sh setup` — loads fake notes and fake clips (your real notes are backed up; `./Video/demo.sh restore` puts them back).
2. Set the theme in Settings (Cyber Black looks best on dark wallpapers).
3. Clean the screen: clean wallpaper, hide Dock and desktop icons, Do Not Disturb on, close other apps.
4. Make the Pasteboard window large (about 1100×700) so text is readable at video size.
5. Turn on **Capture screenshots** in Settings (shot 4 uses it).
6. Open `Video/assets` in a Finder window next to a second empty folder named "Project" (shot 4).
7. Optional: for different source-app icons on the clips, copy a few things by hand from Safari, Notes and Xcode instead of using `demo.sh clips`.

Recording: ⌘⇧5 → "Record Selected Portion", mic off. Move the mouse slowly and pause ~1s after every action — pauses can be trimmed, missing pauses can't be added.

## Shots

| # | Time | On screen | What you do | Caption |
|---|------|-----------|-------------|---------|
| 1 | 0–4s | Any app. Copy three things in a row (text, link, text). | ⌘C on each, with a short pause. | "You copy a lot." |
| 2 | 4–10s | Press ⌘⇧F; the window opens with the history. | Type a word in search, click a clip to copy it, paste into the app. | "Everything you copied. One shortcut away." |
| 3 | 10–16s | Pause on the list: text, a link, code, an image, a file. | Slowly hover down the list; open the code clip so the syntax colours show. | "Text, links, code, images, files." |
| 4 | 16–26s | Stack mode. | Turn stack mode on (stack icon). Copy a sentence, then the two images and `Q4-Report.pdf` from `Video/assets`. Turn stack off. Paste into the "Project" folder in Finder. | "Stack it. Paste it all at once." |
| 5 | 26–32s | Notes page. | Click Note. Open "Work Logins", click a field to copy it ("✓ Copied"), then show the pinned note and the image note. | "Logins, addresses, snippets — one click to copy." |
| 6 | 32–35s | Settings → Theme grid, or the window on a clean wallpaper. | Switch a theme or two. | "Dark. Fast. Native." |
| 7 | 35–39s | End card (added in editing). | — | Logo · **Pasteboard** · "Free & open source" · github.com/nahid0-0/Pasteboard |

## Editing notes

- Speed up the dull moments (typing, waiting) to 1.5–2×; keep clicks and copy confirmations at normal speed.
- Zoom in slightly on the window for shots 3–5; Screen Studio does this automatically, otherwise I can crop and zoom with ffmpeg.
- Music: something calm and rhythmic, low volume; cut on the beat between shots.
- Exports: 1080p MP4 for YouTube / X / LinkedIn, a short looping WebP/GIF for the GitHub README (same as the existing preview), and a 9:16 crop for Reels/Shorts.

## After filming

`./Video/demo.sh restore`
