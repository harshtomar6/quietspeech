// Timeline helpers for the Notch overlay (named QSCapsule so the scenes stay
// as they were). Every value comes from a seeded generator, so any frame
// renders the same on its own.
(function () {
  const NW = 210;          // notch width, as .cap --nw
  const NH = 40;           // notch height = menu bar height
  const OPEN_W = 720;      // notch plus the two wings
  const OPEN_H = 116;      // plus the row of live words
  const STRIP_W = 600;     // "Inserted" strip, level with the notch

  function rng(seed) {
    let s = seed % 2147483647;
    return function () {
      s = (s * 16807) % 2147483647;
      return (s - 1) / 2147483646;
    };
  }

  function el(cls, children) {
    const d = document.createElement("div");
    d.className = cls;
    (children || []).forEach(function (c) { if (c) d.appendChild(c); });
    return d;
  }

  // Rebuild the scene's capsule markup as the island. Runs once, at load.
  function build(cap) {
    if (cap.querySelector(".qn-island")) return cap.querySelector(".qn-island");
    const wave = cap.querySelector(".cap-wave");
    if (wave) wave.remove();
    const icon = cap.querySelector(".cap-icon");
    const status = cap.querySelector(".cap-status");
    const text = cap.querySelector(".cap-text");
    const time = cap.querySelector(".cap-time");
    const doneEl = el("qn-done", [cap.querySelector(".cap-check")]);
    doneEl.appendChild(document.createTextNode("Inserted"));
    const row = el("qn-row", [
      el("qn-lead", [icon]),
      el("qn-cut"),
      el("qn-trail", [time, status, doneEl]),
    ]);
    const body = el("qn-body", [row, el("qn-text", [text])]);
    const island = el("qn-island", [el("qn-glow"), el("qn-rim"), body]);
    cap.appendChild(island);
    return island;
  }

  function q(cap, sel) { return cap.querySelector(sel); }

  function setup(tl, cap) {
    build(cap);
    tl.set(cap, { opacity: 0 }, 0);
    tl.set(q(cap, ".qn-island"), { width: NW, height: NH, "--nr": "16px" }, 0);
  }

  // Opens out of the notch with the app's spring.
  function enter(tl, cap, t) {
    const island = q(cap, ".qn-island");
    tl.set(cap, { opacity: 1 }, t);
    tl.to(island, { width: OPEN_W, height: OPEN_H, "--nr": "38px", duration: 0.46, ease: "back.out(1.25)" }, t);
    tl.to(cap.querySelectorAll(".qn-lead, .qn-trail, .qn-text"), { opacity: 1, duration: 0.22, ease: "power2.out" }, t + 0.16);
    tl.to(q(cap, ".qn-rim"), { opacity: 1, duration: 0.25 }, t + 0.1);
    tl.set(q(cap, ".qn-glow"), { opacity: 0.4 }, t + 0.1);
  }

  // The rim turns all the while; the glow follows the voice level, one
  // step every 90 ms like the app's meter.
  function wave(tl, cap, t0, t1, seed) {
    const glow = q(cap, ".qn-glow");
    const next = rng(seed);
    tl.fromTo(cap, { "--qa": "0deg" }, { "--qa": ((t1 - t0 + 3) * 80).toFixed(0) + "deg", duration: t1 - t0 + 3, ease: "none" }, t0);
    for (let t = t0; t < t1; t += 0.09) {
      tl.to(glow, { opacity: 0.35 + 0.65 * next(), duration: 0.08, ease: "none" }, t);
    }
    tl.to(glow, { opacity: 0.45, duration: 0.15 }, t1);
  }

  // Let go: the timer gives way to a spinner and the rim spins faster.
  function processing(tl, cap, t) {
    tl.to(q(cap, ".cap-time"), { opacity: 0, duration: 0.12 }, t);
    tl.fromTo(q(cap, ".cap-spin"), { opacity: 0 }, { opacity: 1, duration: 0.15 }, t);
    tl.fromTo(q(cap, ".cap-spin"), { rotation: 0 }, { rotation: 900, duration: 2.5, ease: "none" }, t);
    tl.fromTo(cap, { "--qb": "0deg" }, { "--qb": "540deg", duration: 2.5, ease: "none" }, t);
  }

  // Done: a strip level with the notch, with "Inserted".
  function done(tl, cap, t) {
    const island = q(cap, ".qn-island");
    tl.to(q(cap, ".cap-spin"), { opacity: 0, duration: 0.1 }, t);
    tl.to(q(cap, ".qn-text"), { opacity: 0, duration: 0.12 }, t);
    tl.to(island, { width: STRIP_W, height: NH, "--nr": "16px", duration: 0.34, ease: "power3.out" }, t);
    tl.to(cap.querySelectorAll(".qn-rim, .qn-glow"), { opacity: 0, duration: 0.3 }, t);
    tl.fromTo(q(cap, ".qn-done"), { opacity: 0 }, { opacity: 1, duration: 0.2 }, t + 0.08);
    tl.fromTo(q(cap, ".cap-check"), { scale: 0.4 }, { scale: 1, duration: 0.32, ease: "back.out(2)" }, t + 0.08);
  }

  // Folds back into the notch.
  function leave(tl, cap, t) {
    const island = q(cap, ".qn-island");
    tl.to(cap.querySelectorAll(".qn-lead, .qn-trail"), { opacity: 0, duration: 0.14 }, t);
    tl.to(island, { width: NW, duration: 0.32, ease: "power3.inOut" }, t);
    tl.set(cap, { opacity: 0 }, t + 0.34);
  }

  // Words appear in the live line as they are heard.
  function words(tl, cap, selector, t0, step) {
    const live = cap.querySelector(selector);
    tl.set(cap.querySelectorAll(".ph"), { display: "none" }, t0);
    tl.set(live, { display: "inline-block" }, t0);
    live.querySelectorAll(".w").forEach(function (w, i) {
      tl.set(w, { display: "inline" }, t0 + i * step);
    });
  }

  // Swap the raw transcript for the cleaned one.
  function swapLive(tl, cap, from, to, t) {
    tl.set(cap.querySelector(from), { display: "none" }, t);
    tl.set(cap.querySelector(to), { display: "inline-block" }, t);
    tl.set(cap.querySelectorAll(to + " .w"), { display: "inline" }, t);
  }

  function timer(tl, cap, times) {
    const spans = cap.querySelectorAll(".cap-time span");
    times.forEach(function (t, i) {
      tl.set(spans[i], { opacity: 0 }, t);
      tl.set(spans[i + 1], { opacity: 1 }, t);
    });
  }

  window.QSCapsule = { wave, processing, done, words, swapLive, timer, enter, leave, setup, build };
})();

// The brand world: the icon's glossy cyan ribbons, stretched into long waves
// behind every scene. Each band is periodic in its wavelength and drifts at a
// fixed speed in film time, so cuts between scenes don't jump.
(function () {
  const NS = "http://www.w3.org/2000/svg";
  const BANDS = [
    { y: 640, amp: 110, lam: 1500, ph: 0.6, th: 120, op: 0.22, blur: 22, speed: 24 },
    { y: 760, amp: 130, lam: 1150, ph: 2.1, th: 58, op: 0.55, blur: 4, speed: 38 },
    { y: 840, amp: 70, lam: 1800, ph: 4.0, th: 26, op: 0.42, blur: 1.5, speed: 18 },
  ];

  // Portrait formats keep the ribbons low, under the reading band.
  function bandY(b) {
    const H = window.QS_H || 1080;
    if (H === 1080) return b.y;
    return H - (1080 - b.y) * (H > 1600 ? 1.4 : 0.85);
  }

  function bandPath(b) {
    const top = [];
    const bottom = [];
    const end = (window.QS_W || 1920) + b.lam + 900;
    for (let x = -120; x <= end; x += 16) {
      const yt = bandY(b) + b.amp * Math.sin((2 * Math.PI * x) / b.lam + b.ph);
      const t = b.th * (0.18 + 0.82 * Math.abs(Math.sin((Math.PI * x) / b.lam + b.ph * 0.5)));
      top.push(x.toFixed(1) + " " + yt.toFixed(1));
      bottom.unshift(x.toFixed(1) + " " + (yt + t).toFixed(1));
    }
    return "M" + top.join(" L") + " L" + bottom.join(" L") + " Z";
  }

  // start: this scene's start in film seconds; dur: its length.
  function ribbons(tl, svg, start, dur, opts) {
    const o = opts || {};
    const W = window.QS_W || 1920;
    const H = window.QS_H || 1080;
    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    svg.style.width = W + "px";
    svg.style.height = H + "px";
    const gid = svg.id + "-g";
    const defs = document.createElementNS(NS, "defs");
    defs.innerHTML =
      '<linearGradient id="' + gid + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="#d9fdfe"/>' +
      '<stop offset="0.45" stop-color="#5ce1e6"/>' +
      '<stop offset="1" stop-color="#0e8fa3"/></linearGradient>';
    svg.appendChild(defs);
    return BANDS.map(function (b) {
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", bandPath(b));
      p.setAttribute("fill", "url(#" + gid + ")");
      p.style.opacity = String(b.op * (o.strength || 1));
      p.style.filter = "blur(" + b.blur + "px)";
      svg.appendChild(p);
      const off = -((b.speed * start) % b.lam);
      tl.fromTo(p, { x: off }, { x: off - b.speed * dur, duration: dur, ease: "none" }, 0);
      return p;
    });
  }

  window.QSWorld = { ribbons };
})();
