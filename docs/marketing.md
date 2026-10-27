# QuietSpeech — marketing memory

Reviewed: 2026-10-26. Public assets come from the repository; the owner confirmed that the product has just launched and no marketing campaigns or channels are active yet.

## Direction

- Primary audience: Mac users who want dictation without a monthly payment.
- Intended one-sentence promise: fast, easy, private dictation for Mac with no recurring subscription. Treat “fast” and “easy” as experience goals unless evidence supports measurable claims.
- Lead with dictation and the one-time purchase. Editing and generation are supporting capabilities.

## Current public-facing assets and messages

- [quietspeech.app site source](../landing/index.html): hero, interactive demo, three workflows, privacy explanation, pricing, FAQ, checkout links, and download link.
- Main line: “Say it, and it’s written.” Supporting line (live since 2026-10-27): “Dictate, edit, and generate text in any Mac app. It runs on Apple Intelligence, so there’s no API key to set up.” It replaced “… On-device by default.”
- Differentiator strip under the hero (live since 2026-10-27, matching the launch film): No API key, Apple Intelligence built in, Works offline, Under 60 MB of memory. It replaced three privacy lines that the Privacy section already covers. The FAQ gained “Do I need an API key?” and “How much memory does it use?”, and the offline answer now opens with “Yes, by default.”
- Launch film on the site (live since 2026-10-27): a “Watch the film 0:43” link in the hero opens a dialog that plays `landing/assets/film/quietspeech-film-720.mp4` with sound, or the 4:5 `quietspeech-film-feed.mp4` on phones in portrait (about 2.3 MB each; nothing loads until clicked). Clicks are tracked as the Minilytics goal `film_play`. Without JavaScript, the link opens the MP4.
- Offer displayed: $29 once, two Mac activations, no subscription or account, 14-day refund.
- The site emphasizes local processing, Mac-native design, and the option to use other AI providers. For exact caveats, use [product.md](product.md).
- [Design system](../design/DESIGN_SYSTEM.md) records interface and brand direction; [icons](../icons/README.md) holds asset guidance.
- **Published on the site 2026-10-27 (not yet on social):** a 43 s launch film built with HyperFrames in [video/](../video/SPEC.md) (2026-10-27). It uses the site’s copy and demo scenes, set in the app icon’s navy-and-cyan world (rebuilt the same day after the first cut looked like a wireframe). The owner then asked it to lead with differentiators so it doesn't read as another dictation app: no API key, Apple Intelligence built in, works offline, under 60 MB of memory, fast. The capsule is rebuilt from `Sources/QuietSpeech/HUD.swift`, not screen-recorded, and the music bed is generated with ElevenLabs (check that the plan allows commercial use before publishing). It renders in 16:9, 4:5 (feeds) and 9:16 (Reels, TikTok, Shorts); see the Formats section of video/REVIEW.md. See [video/REVIEW.md](../video/REVIEW.md) for known gaps.

## Measurement present in the repository

- The landing page includes a Minilytics script and goal attributes for checkout, demo, pricing, and download interactions. See [site source](../landing/index.html).
- The repository does not contain verified traffic, conversion, sales, or campaign results. Do not infer performance from tracking code.

## Active channels and experiments

None yet, per the owner on 2026-10-26. The launch site and its tracking are in place; no campaign results exist in this memory.

For each future experiment, record the audience, message, channel, start/end dates, success measure, result, evidence link, and next decision. Keep daily metrics in the analytics source and put only the interpreted learning here.

## Claims checklist

- Check feature availability, platform requirements, provider behavior, and license terms against [product.md](product.md) before publishing copy.
- Say “on-device by default,” because optional external providers can receive audio or text.
- Differentiators the owner approved for the launch film (2026-10-27): “No API key” (true by default; keys are only for optional providers), “Apple Intelligence, built in” (local polish, edit and generate when it's available), and “Works offline”, paired with “On-device by default” (licence checks allow 14 days offline; optional providers need the network).
- Memory: the running app measured 58 MB physical footprint at idle (`footprint`, 2026-10-27), so say “under 60 MB”, not “50 MB”. Re-measure during dictation before quoting a figure elsewhere.
- “Fast” stays qualitative; there's no latency measurement in the repo.
- Keep app telemetry and website analytics distinct.
- Avoid claims about customer demand, performance, conversion, or competitors until supported by evidence.
