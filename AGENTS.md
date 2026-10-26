# QuietSpeech agent guide

Before project work, read [docs/brief.md](docs/brief.md). Read the relevant product, audience, marketing, and decision files before making claims or changing behavior.

Before finishing any task, follow [docs/MEMORY_POLICY.md](docs/MEMORY_POLICY.md): review whether the work makes a durable project fact stale, update the relevant Markdown in the same branch when it does, and state which files changed or why none needed to change. Do not turn unverified assumptions into facts.

For code changes, run the relevant checks. `swift test` is the unit-test entry point; `./build-app.sh` builds the Mac app. Follow [README.md](README.md) for platform and signing requirements.

Treat the current working tree as user work. Preserve unrelated changes, including uncommitted files.
