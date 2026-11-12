#!/usr/bin/env python3
"""Keep quietspeech.app in step with app releases.

Release notes live in docs/releases/<version>.md:

    # QuietSpeech 0.3.7

    Released: 2026-11-12

    - One customer-facing change per bullet.

Commands (run from anywhere; paths resolve from the repo root):

  notes VERSION --appcast-dir DIR
      Write DIR/QuietSpeech-VERSION.html from the notes file, so Sparkle's
      generate_appcast (run by package.sh) puts the notes in the feed.
      Run this BEFORE package.sh.

  site VERSION [--appcast-dir DIR]
      After package.sh: copy DIR/appcast.xml and every DMG/delta it lists into
      landing/, rebuild landing/changelog.html from all notes files, point every
      download link at the VERSION DMG, update the founder card's version and
      the sitemap, then run `check`.

  check
      Fail if any download path in the site or feed is missing from
      landing/downloads/, or if the notes, feed, changelog and download links
      disagree about the latest version.
"""
import argparse
import datetime as dt
import html
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTES = ROOT / "docs" / "releases"
LANDING = ROOT / "landing"
DOWNLOADS = LANDING / "downloads"
CHANGELOG = LANDING / "changelog.html"
SITEMAP = LANDING / "sitemap.xml"
APPCAST = LANDING / "appcast.xml"

VERSION_RE = r"\d+(?:\.\d+)+"
DMG_REF = re.compile(r"downloads/(QuietSpeech-" + VERSION_RE + r"\.dmg|QuietSpeech\d+-\d+\.delta)")


def vkey(v):
    return tuple(int(p) for p in v.split("."))


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def read_notes(version):
    path = NOTES / f"{version}.md"
    if not path.exists():
        fail(f"{path.relative_to(ROOT)} is missing. Write the release notes first.")
    text = path.read_text()
    m = re.search(r"^Released:\s*(\d{4}-\d{2}-\d{2})\s*$", text, re.M)
    if not m:
        fail(f"{path.name} needs a 'Released: YYYY-MM-DD' line.")
    items = [line[2:].strip() for line in text.splitlines() if line.startswith("- ")]
    if not items:
        fail(f"{path.name} has no '- ' bullet points.")
    return dt.date.fromisoformat(m.group(1)), items


def all_versions():
    vs = [p.stem for p in NOTES.glob("*.md") if re.fullmatch(VERSION_RE, p.stem)]
    return sorted(vs, key=vkey, reverse=True)


def long_date(d):
    return f"{d.day} {d.strftime('%B %Y')}"


def replace_block(text, name, body):
    pat = re.compile(rf"(<!-- {name}:start -->)(.*?)(\s*<!-- {name}:end -->)", re.S)
    if not pat.search(text):
        fail(f"changelog.html is missing the <!-- {name}:start/end --> markers.")
    return pat.sub(lambda m: m.group(1) + body + m.group(3), text, count=1)


# ---- notes -----------------------------------------------------------------

def cmd_notes(args):
    _, items = read_notes(args.version)
    out = Path(args.appcast_dir).expanduser() / f"QuietSpeech-{args.version}.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    lis = "\n".join(f"<li>{html.escape(i, quote=False)}</li>" for i in items)
    out.write_text(f"<h2>QuietSpeech {args.version}</h2>\n<ul>\n{lis}\n</ul>\n")
    print(f"wrote {out}")


# ---- site ------------------------------------------------------------------

def copy_artifacts(src_dir):
    src = Path(src_dir).expanduser()
    feed = src / "appcast.xml"
    if not feed.exists():
        fail(f"{feed} not found. Did package.sh run with this APPCAST_DIR?")
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    copied = 0
    for name in sorted(set(DMG_REF.findall(feed.read_text()))):
        dest = DOWNLOADS / name
        if dest.exists():
            continue
        if not (src / name).exists():
            fail(f"the feed lists {name}, but it is not in {src}.")
        shutil.copy2(src / name, dest)
        copied += 1
    shutil.copy2(feed, APPCAST)
    print(f"copied appcast.xml and {copied} new download file(s) into landing/")


def render_changelog(latest):
    versions = all_versions()
    if not versions or versions[0] != latest:
        fail(f"{latest} is not the newest notes file in docs/releases (newest: {versions[0] if versions else 'none'}).")
    date, _ = read_notes(latest)
    latest_html = f"""
      <div class="changelog-latest">
        <div class="changelog-latest-copy">
          <p class="changelog-latest-label">Latest version</p>
          <p class="changelog-latest-version">QuietSpeech {latest} &middot; {long_date(date)}</p>
          <p class="changelog-latest-note">For macOS 26 on Apple silicon. Activate it with your license key from the purchase email.</p>
        </div>
        <a class="btn btn-primary" href="/downloads/QuietSpeech-{latest}.dmg" download data-ml-goal="download_click" data-ml-goal-location="changelog">Download QuietSpeech {latest}</a>
      </div>"""
    parts = []
    for v in versions:
        d, items = read_notes(v)
        tag = '\n          <span class="release-tag">Latest</span>' if v == latest else ""
        lis = "\n".join(f"          <li>{html.escape(i, quote=False)}</li>" for i in items)
        parts.append(f"""
      <article class="release" id="v{v}">
        <div class="release-head">
          <h2><a href="#v{v}">QuietSpeech {v}</a></h2>
          <time datetime="{d.isoformat()}">{long_date(d)}</time>{tag}
        </div>
        <ul class="release-notes">
{lis}
        </ul>
      </article>""")
    text = CHANGELOG.read_text()
    text = replace_block(text, "latest", latest_html)
    text = replace_block(text, "releases", "".join(parts))
    CHANGELOG.write_text(text)
    print(f"rebuilt changelog.html with {len(versions)} releases")
    return date


def point_downloads(version):
    changed = []
    for page in sorted(LANDING.glob("*.html")):
        text = page.read_text()
        new = re.sub(r"downloads/QuietSpeech-" + VERSION_RE + r"\.dmg", f"downloads/QuietSpeech-{version}.dmg", text)
        new = re.sub(r"(Download QuietSpeech )" + VERSION_RE, rf"\g<1>{version}", new)
        new = re.sub(r'(on <a href="/changelog">version )' + VERSION_RE, rf"\g<1>{version}", new)
        if new != text:
            page.write_text(new)
            changed.append(page.name)
    print("download links and version mentions updated in: " + (", ".join(changed) or "nothing (already current)"))


def update_sitemap(date):
    text = SITEMAP.read_text()
    iso = date.isoformat()
    if "https://quietspeech.app/changelog" not in text:
        text = text.replace("</urlset>", f"  <url>\n    <loc>https://quietspeech.app/changelog</loc>\n    <lastmod>{iso}</lastmod>\n  </url>\n</urlset>")
    for loc in ("https://quietspeech.app/", "https://quietspeech.app/changelog"):
        pat = re.compile(rf"(<loc>{re.escape(loc)}</loc>\s*<lastmod>)(\d{{4}}-\d{{2}}-\d{{2}})(</lastmod>)")
        text = pat.sub(lambda m: m.group(1) + max(m.group(2), iso) + m.group(3), text)
    SITEMAP.write_text(text)


def cmd_site(args):
    if args.appcast_dir:
        copy_artifacts(args.appcast_dir)
    date = render_changelog(args.version)
    point_downloads(args.version)
    update_sitemap(date)
    return cmd_check(args)


# ---- check -----------------------------------------------------------------

def cmd_check(_args=None):
    problems = []
    refs = {}
    for page in [APPCAST, *sorted(LANDING.glob("*.html"))]:
        for name in DMG_REF.findall(page.read_text()):
            refs.setdefault(name, page.name)
    for name, where in sorted(refs.items()):
        if not (DOWNLOADS / name).exists():
            problems.append(f"{where} links downloads/{name}, which is missing from landing/downloads/")

    newest_notes = (all_versions() or ["none"])[0]
    feed = APPCAST.read_text()
    feed_versions = re.findall(r"<sparkle:shortVersionString>(" + VERSION_RE + r")</sparkle:shortVersionString>", feed)
    newest_feed = max(feed_versions, key=vkey) if feed_versions else "none"
    site_links = set()
    for page in LANDING.glob("*.html"):
        site_links.update(re.findall(r"downloads/QuietSpeech-(" + VERSION_RE + r")\.dmg", page.read_text()))
    m = re.search(r'class="changelog-latest-version">QuietSpeech (' + VERSION_RE + ")", CHANGELOG.read_text())
    newest_changelog = m.group(1) if m else "none"

    if newest_feed != newest_notes:
        problems.append(f"feed's newest version is {newest_feed}, but the newest notes file is {newest_notes}")
    if site_links != {newest_notes}:
        problems.append(f"site download links point at {sorted(site_links)}, expected only {newest_notes}")
    if newest_changelog != newest_notes:
        problems.append(f"changelog shows {newest_changelog} as latest, expected {newest_notes}")

    if problems:
        print("check failed:")
        for p in problems:
            print(f"  - {p}")
        sys.exit(1)
    print(f"check passed: notes, feed, changelog and download links all at {newest_notes}; {len(refs)} download files present")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    n = sub.add_parser("notes")
    n.add_argument("version")
    n.add_argument("--appcast-dir", required=True)
    s = sub.add_parser("site")
    s.add_argument("version")
    s.add_argument("--appcast-dir")
    sub.add_parser("check")
    args = ap.parse_args()
    {"notes": cmd_notes, "site": cmd_site, "check": cmd_check}[args.cmd](args)


if __name__ == "__main__":
    main()
