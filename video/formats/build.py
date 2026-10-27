#!/usr/bin/env python3
"""Derive the portrait format projects from the landscape film.

index.html stays the one source for timing, scenes and sound. Each format
gets formats/<name>/ (generated, not committed): index.html with its own size
and a format flag the scenes read (window.QS_FORMAT, <html data-qs>), copies
of compositions/ with the scene roots resized, and a copy of assets/. Edit the
sources in video/, never the copies.

Run from video/: python3 formats/build.py, then render each format with
npx hyperframes render formats/<name> -o renders/quietspeech-launch-<name>.mp4
"""
import json
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

FORMATS = {
    "feed": (1080, 1350),  # 4:5: Instagram and Facebook feed, X and LinkedIn mobile feed
    "tall": (1080, 1920),  # 9:16: Reels, TikTok, Shorts, Stories
}


def flag(name, w, h):
    return (
        "<script>window.QS_FORMAT = %s; window.QS_W = %d; window.QS_H = %d;"
        " document.documentElement.dataset.qs = %s;</script>"
        % (json.dumps(name), w, h, json.dumps(name))
    )


def localize(css, name):
    """Scene CSS is scoped to the scene root at compile time, so a rule keyed
    on <html data-qs> never matches. Each copy turns its own format's rules
    into plain selectors (later in the file, so they win) and disables the
    other formats' rules."""
    for other in FORMATS:
        css = css.replace('html[data-qs="%s"] ' % other,
                          "" if other == name else "html[data-qs-off] ")
    return css


def main():
    src = open(os.path.join(ROOT, "index.html")).read()
    for name, (w, h) in FORMATS.items():
        out = src.replace('<html lang="en">', '<html lang="en" data-qs="%s">' % name)
        out = out.replace(
            '<meta name="viewport" content="width=1920, height=1080" />',
            '<meta name="viewport" content="width=%d, height=%d" />' % (w, h),
        )
        out = out.replace("<title>QuietSpeech launch film</title>",
                          "<title>QuietSpeech launch film (%s)</title>" % name)
        out = out.replace("    <script src=\"assets/capsule.js\"></script>",
                          "    " + flag(name, w, h) + "\n    <script src=\"assets/capsule.js\"></script>")
        out = out.replace("width: 1920px;\n        height: 1080px;",
                          "width: %dpx;\n        height: %dpx;" % (w, h))
        out = re.sub(r'data-width="1920"', 'data-width="%d"' % w, out)
        out = re.sub(r'data-height="1080"', 'data-height="%d"' % h, out)
        assert out.count('data-width="%d"' % w) >= 6, name

        d = os.path.join(HERE, name)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "index.html"), "w").write(out)
        for sub in ("compositions", "assets"):
            p = os.path.join(d, sub)
            if os.path.islink(p):
                os.unlink(p)
            elif os.path.isdir(p):
                shutil.rmtree(p)
        shutil.copytree(os.path.join(ROOT, "assets"), os.path.join(d, "assets"))
        ui = os.path.join(d, "assets", "ui.css")
        css = localize(open(ui).read(), name)
        open(ui, "w").write(css)
        os.makedirs(os.path.join(d, "compositions"))
        for f in os.listdir(os.path.join(ROOT, "compositions")):
            if not f.endswith(".html"):
                continue
            scene = open(os.path.join(ROOT, "compositions", f)).read()
            scene = scene.replace('data-width="1920" data-height="1080"',
                                  'data-width="%d" data-height="%d"' % (w, h))
            open(os.path.join(d, "compositions", f), "w").write(localize(scene, name))
        for cfg in ("hyperframes.json",):
            open(os.path.join(d, cfg), "w").write(open(os.path.join(ROOT, cfg)).read())
        open(os.path.join(d, "meta.json"), "w").write(
            json.dumps({"id": "video-" + name, "name": "video-" + name}, indent=2) + "\n")
        print("wrote", os.path.relpath(d, ROOT), w, "x", h)


if __name__ == "__main__":
    main()
