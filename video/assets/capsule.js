// Timeline helpers for the capsule overlay. Every value comes from a seeded
// generator, so any frame renders the same on its own.
(function () {
  function rng(seed) {
    let s = seed % 2147483647;
    return function () {
      s = (s * 16807) % 2147483647;
      return (s - 1) / 2147483646;
    };
  }

  // The app's meter: bars scroll in from the right, one step every 90 ms.
  function wave(tl, cap, t0, t1, seed) {
    const bars = Array.from(cap.querySelectorAll(".cap-wave i"));
    const next = rng(seed);
    const levels = bars.map(function () { return 0.14; });
    for (let t = t0; t < t1; t += 0.09) {
      levels.shift();
      levels.push(0.12 + 0.8 * next());
      bars.forEach(function (bar, i) {
        tl.to(bar, {
          scaleY: Math.max(0.21, levels[i]),
          opacity: 0.55 + 0.45 * levels[i],
          duration: 0.08,
          ease: "none",
        }, t);
      });
    }
    tl.to(bars, { scaleY: 0.21, opacity: 0.45, duration: 0.12, ease: "power2.out" }, t1);
  }

  // Listening -> spinner -> green check, as StatusIndicator swaps them.
  function processing(tl, cap, t) {
    tl.to(cap.querySelector(".cap-wave"), { opacity: 0, duration: 0.15 }, t);
    tl.fromTo(cap.querySelector(".cap-spin"), { opacity: 0 }, { opacity: 1, duration: 0.15 }, t);
    tl.fromTo(cap.querySelector(".cap-spin"), { rotation: 0 }, { rotation: 900, duration: 2.5, ease: "none" }, t);
  }

  function done(tl, cap, t) {
    tl.to(cap.querySelector(".cap-spin"), { opacity: 0, duration: 0.12 }, t);
    tl.fromTo(cap.querySelector(".cap-check"),
      { opacity: 0, scale: 0.4 },
      { opacity: 1, scale: 1, duration: 0.32, ease: "back.out(2)" }, t);
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

  // The overlay's entrance spring and its 220 ms fade out.
  function enter(tl, cap, t) {
    tl.fromTo(cap, { opacity: 0, y: 5, scale: 0.985 },
      { opacity: 1, y: 0, scale: 1, duration: 0.3, ease: "back.out(1.2)" }, t);
  }

  function leave(tl, cap, t) {
    tl.to(cap, { opacity: 0, y: 5, duration: 0.22, ease: "power2.in" }, t);
  }

  function setup(tl, cap) {
    tl.set(cap.querySelectorAll(".cap-wave i"), { scaleY: 0.21, opacity: 0.55 }, 0);
  }

  window.QSCapsule = { wave, processing, done, words, swapLive, timer, enter, leave, setup };
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
