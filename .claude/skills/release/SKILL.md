---
name: release
description: Ship a new QuietSpeech version end to end. Writes customer-facing release notes, builds and notarizes the DMG with package.sh, publishes the Sparkle feed, updates the /changelog page and every download link on quietspeech.app so new users always get the latest build, deploys, and verifies. Use whenever the user says to release, ship, publish or cut a new QuietSpeech version (e.g. "release 0.3.7", "ship this fix", "publish a new build").
---

# Release QuietSpeech

A release has three outputs that must agree: the notarized DMG, the Sparkle feed
(`appcast.xml`), and the website (download links, `/changelog`). The site
helper `scripts/release_site.py` keeps them in step; this skill runs the release
around it. Read `scripts/release_site.py --help` once before starting.

## Fixed locations

| Name | Path | Why |
|---|---|---|
| `SITE` | `~/dev/whispr-flow-alt` | The only checkout with `landing/.vercel` and the full, git-ignored `landing/downloads/`. Deploy only from `SITE/landing`. |
| `APPCAST_DIR` | `~/dev/whispr-flow-alt/dist/appcast` | Holds every DMG, delta and `QuietSpeech-<v>.html` notes file ever shipped. `generate_appcast` rebuilds the feed from this folder, so always pass it as an absolute path, even when building in a worktree. |
| `CODE` | the checkout with the release's code | Usually a worktree on `release/<version>` made from `origin/main`. Commits go here, never to `SITE`'s current branch unless it is that release branch. |

## Steps

### 1. Pre-flight (stop and report if anything fails)

1. `CODE` is clean apart from the release's own changes and is based on current `origin/main` (`git fetch`, then check `git log HEAD..origin/main` is empty).
2. Pick the version. Read the newest `<sparkle:version>` (build number) and `<sparkle:shortVersionString>` from `SITE/landing/appcast.xml`. `BUILD_NUMBER` = newest build number + 1, always. If the user didn't give a version, propose the next patch version and confirm.
3. `APPCAST_DIR` contains every file the live feed lists: for each `downloads/...` path in `SITE/landing/appcast.xml`, the file exists in `APPCAST_DIR`; copy any missing one from `SITE/landing/downloads/`. A missing older DMG or notes file makes `generate_appcast` drop that entry or its notes.
4. `cd SITE && python3 scripts/release_site.py check` passes. It proves the current site, feed and downloads agree before you change anything.
5. `vercel whoami` succeeds. If not, ask the user to run `! vercel login`.

### 2. Release notes

Write `CODE/docs/releases/<version>.md`:

```
# QuietSpeech <version>

Released: <YYYY-MM-DD, today>

- One change per bullet, as the user experiences it.
```

Source the bullets from `git log <previous release commit>..HEAD` in `CODE`. Rules:

- Describe what the user notices, not the implementation: "Command-Tab works while QuietSpeech is listening", not "Fix CGEvent passthrough in ShortcutMatcher".
- Full sentences in plain language, no internal names (class names, file names, branch names), no dashes as punctuation.
- Leave out changes users can't see (refactors, tests, build scripts, docs, the website).
- Never claim more than the commits show. Keep numbers exactly as measured.

**Show the notes, version and build number to the user and wait for approval.** These go public in the app's update window, the feed and the changelog.

### 3. Build

From `CODE`:

1. `swift test`. All tests must pass.
2. `python3 scripts/release_site.py notes <version> --appcast-dir ~/dev/whispr-flow-alt/dist/appcast`. It must run before packaging so the notes land in the feed.
3. `VERSION=<version> BUILD_NUMBER=<n> APPCAST_DIR=~/dev/whispr-flow-alt/dist/appcast ./package.sh`
   - Notarization uses the keychain profile `quietspeech-notary`. A 403 "agreement missing" means the user must accept the updated Apple Developer agreement; stop and tell them.
   - Afterwards confirm `APPCAST_DIR` has `QuietSpeech-<version>.dmg`, new `QuietSpeech<n>-*.delta` files, and an `appcast.xml` whose newest item is this version with the notes.

### 4. Update the site

1. Copy `CODE/docs/releases/<version>.md` to `SITE/docs/releases/` (and `CODE/scripts/release_site.py` if it changed).
2. `cd SITE && python3 scripts/release_site.py site <version> --appcast-dir ~/dev/whispr-flow-alt/dist/appcast`
   This copies the feed and every DMG/delta it lists into `landing/`, rebuilds `/changelog`, moves every download link and the founder card's version to the new DMG, updates the sitemap, and runs `check`. It must end with "check passed".
3. Preview `SITE/landing` locally (`python3 -m http.server` from `landing/`, open `changelog.html` and `index.html`) and show the user the changelog's new entry.
4. Bring the site changes into `CODE`: for every file in `git -C CODE ls-files landing docs/releases`, copy the `SITE` version over. Then verify that every git-tracked file under `CODE/landing` is byte-identical to `SITE/landing`. If anything else differs (unrelated uncommitted site work in `SITE`), stop and ask the user, because the deploy would publish it.

### 5. Deploy and verify

1. `cd SITE/landing && vercel deploy --prod --yes`, then confirm the newest deployment is Ready with `vercel ls quietspeech`.
2. Verify on the live site, and report each result:
   - `https://quietspeech.app/appcast.xml`: newest item is `<version>` / build `<n>`.
   - Every `downloads/...` file the live feed lists returns HTTP 200 (this is what existing users' updates fetch).
   - `https://quietspeech.app/downloads/QuietSpeech-<version>.dmg` returns 200.
   - `/`, `/changelog`, `/thanks` and both alternative pages link only `QuietSpeech-<version>.dmg`.
   - `/changelog` shows `<version>` as Latest with today's date.

### 6. Commit and record

1. In `CODE`, commit the code, `docs/releases/<version>.md` and the `landing/` changes with a message like "Release <version>: <headline change>", ending with the repo's attribution line. Push the branch. Ask whether to open a PR or merge into `main`; don't push to `main` unasked.
2. Update the `release-setup` memory: the version and build just shipped, and the next `BUILD_NUMBER`.
3. Tell the user: version and build, the notes as published, the live checks, the commit and branch, and anything skipped.

## Never

- Reuse or lower a `BUILD_NUMBER`. Existing installs would never see the update.
- Deploy from a checkout whose `landing/downloads/` is missing files the feed lists. Run `release_site.py check` first.
- Edit `/changelog` or download links by hand. Change `docs/releases/*.md` and rerun `release_site.py site`.
- Skip notarization for a public release (`SKIP_NOTARIZE=1` is for local testing only).
