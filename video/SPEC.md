# SPEC: QuietSpeech launch film (storyline A)

GOAL:    the viewer gets "hold fn, talk, finished text lands in any Mac app, $29 once" and remembers the name.
OUTPUT:  HyperFrames, 30 fps, in 16:9 (1920 x 1080), 4:5 (1080 x 1350) and 9:16 (1080 x 1920), recomposed per format (formats/build.py). Must read muted (site autoplay, social).
TIME:    43 s x 30 = 1290 frames at 120 BPM: beats every 0.5 s from 0, the drop on the title at 6.0 s; cuts at 6, 9, 28, 38 s are on beats. Music bed from ElevenLabs, edited to the cuts (assets/music/README.md); the picture still reads muted.

LOOK (v2, 2026-10-27, after "it does not look good"):
- World: the app icon's own: navy wallpaper (radial #0B2D3D to #061520 with teal and blue glows) and three glossy cyan ribbons (#D9FDFE to #5CE1E6 to #0E8FA3) that drift at fixed speeds in film time, so they run unbroken across cuts. Bright world for the price: #5CE1E6 with #052A33 ink.
- The Mac: a menu bar whose real QuietSpeech mark (Resources/MenuBarIcon) turns red while dictating, and light Mac windows (#FBFBFD, radius 26) with 28-34 px reading text.
- Type: Inter. Hero lines 112-190 px at 500-600, -0.035 to -0.05em; the price 270 px 700. Accent #5CE1E6 for what is live: "fn.", "written.", "Mac.", @Priya, the CTA.
- Capsule from HUD.swift at 1.9-2.2x, bottom centre, as the app places it.
- Motion blur on (data-motion-blur on the root).

SHOTS:
- 0.0-6.0 hook: "Hold fn." over a keyboard close-up; fn pressed at 0.9 → tilt up to the Mac (1.2) → capsule listens, desk dims, the sentence appears at 112 px as heard → "um," struck and dropped → check → the sentence carries into the note → window falls away.
- 6.0-9.0 title: "Say it, and it's written." on the ribbons, words on the lift; whip left.
- 9.0-28.0 demo, three acts, the spoken line large on the left and the app on the right: 01 Mentions (Slack), whip, 02 Edit (Notes, selection, "Make it shorter."), a reply window opens, 03 Generate (Mail). Whip down out.
- 28.0-38.0 claims, then price. Hard cuts on the beat, alternating navy and bright: "API key." struck through → "No API key." / "Nothing to set up." (28-30); "Apple Intelligence, built in." / "Runs on your Mac." (30-31.5); "Works offline." / "On-device by default." (31.5-33); "Under 60 MB" rolling / "of memory." (33-34); "Fast." (34-35); iris to "$29, once." and "One payment." "Two Macs." "No account." (35-37.6); iris closes.
- 38.0-43.0 end card: the icon lands where the iris closed, the wordmark wipes in, "Hold fn. Speak. Let go." and the quietspeech.app button hold.

BANNED: invented UI states or features; speed numbers or accuracy claims; "100% private"; a memory figure other than the measured one; a price animation implying a former price; product UI tilted in 3D; small UI on an empty ground.

QA: 0.0 (thumbnail reads), 1.45 (tilt mid-move), 3.5 (um dropping), 4.4 (carry mid-move), 7.6 (title), 12.6 (@Priya landed), 18.8 (edit result), 21.15 (reply window opening), 24.6 (generated reply), 30.0, 32.6, 35.7 (wordmark wipe), 38.75.
