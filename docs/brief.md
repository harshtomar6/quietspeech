# QuietSpeech — project brief

Reviewed: 2026-10-26. Product details come from the repository; launch status and audience focus were confirmed by the owner on this date.

QuietSpeech is a macOS menu-bar dictation app for people who do not want to pay monthly for dictation. Its default path transcribes speech on the Mac, uses local cleanup, and inserts text at the cursor. It also supports spoken editing and generation. The owner’s intended promise is **fast, easy, private dictation for Mac with no recurring subscription**. “Fast” and “easy” describe the intended experience, not a measured comparison.

## At a glance

- **Platform:** Apple silicon Macs on macOS 26 or later. Microphone and Accessibility permissions are needed.
- **Stage:** Just publicly launched, confirmed by the owner on 2026-10-26. The site offers version 0.2 and a $29 checkout.
- **Primary audience:** Mac users who want a dictation app without monthly payments.
- **Core workflows:** hold a shortcut and dictate; select text and speak an edit instruction; say “generate” and request a draft.
- **Differentiator presented on the site:** on-device transcription and cleanup by default, no account, and a one-time license. Optional external providers change where selected audio or text is processed.
- **Commercial offer:** $29 one-time license for two Macs, with a 14-day refund policy, shown on the site; the owner confirmed the product is live.
- **Release evidence:** the repository has a 0.2 appcast entry and a 2026-10-25 commit titled “Publish 0.2 on the site and Sparkle feed.”

## Where to look

- [Product](product.md): current capabilities, limits, requirements, and privacy behavior.
- [Audience](audience.md): customer segments, needs, and positioning evidence.
- [Marketing](marketing.md): approved site messaging, channels, and experiments.
- [Decisions](decisions.md): durable choices and their recorded basis.
- [Memory policy](MEMORY_POLICY.md): when and how agents update these files.
- [README](../README.md): build, test, distribution, and repository layout.
- [Missions](https://harshtomar.com/admin/missions): QuietSpeech task tracking. The shared MCP endpoint at `https://harshtomar.com/api/mcp/mcp` exposes this memory and Missions task tools; `list_memory_projects` returns the matching Missions project ID for `create_task`.

## Current marketing state

No marketing campaigns or channels are active yet, per the owner on 2026-10-26. The launch site is the current public asset. Specific growth priorities have not been set in this memory.
