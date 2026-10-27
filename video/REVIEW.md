# Review: QuietSpeech launch film (2026-10-27)

Render: `renders/quietspeech-launch.mp4`, 1920 x 1080, 30 fps, 43.0 s, H.264 + AAC, 8.7 MB.

Version 2 (same day): the first cut read as a wireframe (small dark UI on flat grounds, no camera). It was rebuilt in the icon's world, with a light Mac, the capsule at 2x, big spoken type, camera moves and motion blur. See `SPEC.md` for the look and shots.

## Creative calls

- Built storyline A from `STORYLINES.md`, "One voice, four apps". Not built: B (spoken word as giant kinetic type) and C (a morning of messages).
- The capsule is rebuilt from `Sources/QuietSpeech/HUD.swift`: its sizes, states (Speak now… → live words with head truncation → spinner → green check), entrance spring and 220 ms fade. It was not screen-recorded, because computer use wasn't available in this session. Liquid Glass is approximated the way the landing page approximates it.
- Host windows and all copy come from `landing/index.html`: Priya, the invoice, "Make it shorter.", the generated reply, "Say it, and it's written.", "One payment. Two Macs. No account." App icons are the real ones from Notes, Mail, Slack and `landing/assets/icon-512.png`.
- Text appears in apps all at once after the check, because the app inserts after release, and flashes the accent once. The giant spoken sentence in the hook and the struck-out "um," are illustrations of cleanup, not app UI.
- Music: a catchy 120 BPM instrumental generated with the ElevenLabs Music API (2026-10-27), replacing a calmer 100 BPM piano bed the owner found too flat. The model ignored the plan's section timing (its drop came at 16 s), so the take was edited on the beat: it starts 10 s in, so the drop lands on the title at 6.0 s, and one 8 s phrase repeats so the ending lands at 39 s (recipe in `assets/music/README.md`). The film's beats fall every 0.5 s from 0, and the fn press now lands on the 1.0 s beat. The music sits at `data-volume` 0.6 and dips about 5 dB under each pop and key press. Sound effects are Pixabay-licensed and credited in `assets/sfx/CREDITS.md`. Confirm that the ElevenLabs plan allows commercial use before publishing.

- Differentiators (owner request, 2026-10-27, so it doesn't read as "another dictation app"): a 7 s claims montage replaced "Transcribed on this Mac": no API key, Apple Intelligence built in, works offline (on-device by default), under 60 MB of memory, fast. The owner asked for "50 MB"; the running app measured 58 MB physical footprint at idle, so the film says "Under 60 MB". "Fast" has no number because there's no measurement. Edit and Generate captions now credit Apple Intelligence. The film grew to 43 s, and the music got one more 4 s repeat (see `assets/music/README.md`).

## Formats

| File | Size | For |
| --- | --- | --- |
| `renders/quietspeech-launch.mp4` | 1920 x 1080 (16:9) | YouTube, X, LinkedIn, the site |
| `renders/quietspeech-launch-feed.mp4` | 1080 x 1350 (4:5) | Instagram and Facebook feed; X and LinkedIn mobile feed |
| `renders/quietspeech-launch-tall.mp4` | 1080 x 1920 (9:16) | Reels, TikTok, YouTube Shorts, Stories |

All three are 43 s from the same scenes and sound. The portrait cuts are recomposed, not cropped: one column, the spoken line above the app window, the capsule below it, the montage and price broken onto more lines, and the end-card lockup stacked. In 9:16, all text and the product stay between 168 and 1330 px, clear of the platforms' own UI. `formats/build.py` generates `formats/feed` and `formats/tall` (gitignored) from `index.html` and `compositions/`. Portrait rules in the scenes are written as `html[data-qs="tall"] …`; the build rewrites them into plain selectors because scene CSS is scoped at compile time. Rebuild and render with `python3 formats/build.py`, then `npx hyperframes render formats/<name> -o renders/quietspeech-launch-<name>.mp4`.

Web encodes for the site (`landing/assets/film/`) are made from the renders with `ffmpeg -vf scale=1280:720 -c:v libx264 -preset slow -crf 25 -movflags +faststart -c:a aac -b:a 128k` (864 x 1080 for the 4:5 cut), with posters taken at 28.9 s, the "No API key." slate.

## Measured vs looked at

- `hyperframes check`: passes, no errors.
- Mix: −18.0 LUFS integrated, peak −4.7 dBFS. Key presses only just clear the louder bed. Sound cues sit 1–2 frames before their pictures land; the bed dips about 5 dB under each pop and key press. Measured, not heard.
- Frames: snapshots of every scene, the transitions' mid-points and a one-per-second contact sheet of the final MP4 were looked at, but not at phone width.

## Warnings kept on purpose

- `text_below_floor` on menu bar items and window chrome (19–22 px): UI furniture, not reading text.
- `line_unread` on the inserted Slack, Notes and Mail text (2.5–3.5 s): the same words were already shown large on the left while spoken. Also on the montage sublines (1.2 s for 4 words, just under the 1.27 s floor) and the rolling digits: montage pacing on purpose.
- The hook's giant sentence overlaps the dimmed, blurred desk on purpose (`data-layout-allow-overlap`, `data-layout-ignore` on the dimmed layer).

## Weakest shots, with more time

1. **Real capture:** the capsule is still rebuilt from `HUD.swift`. Recording the real overlay (Settings → Overlay → Preview, or `open QuietSpeech.app --args -previewOverlay YES`) would make it exact, including Liquid Glass.
2. **Reply window opening (21.0–21.3 s):** for a few frames the darkened Notes window shows through the opening Mail window.
3. **No voice yet:** the spoken lines are shown, not heard. A synced dictation voice (not a narrator) is the next lift.
4. **Demo holds:** inserted text holds 2.5–3.5 s; slower readers lean on the large left-hand line.
