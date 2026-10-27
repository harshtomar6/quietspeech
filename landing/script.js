const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const nav = document.getElementById("nav");
const onScroll = () => {
  if (!nav) return;
  nav.classList.toggle("is-scrolled", window.scrollY > 8);
};
onScroll();
window.addEventListener("scroll", onScroll, { passive: true });

const revealItems = document.querySelectorAll("[data-reveal]");
if ("IntersectionObserver" in window && !reduceMotion) {
  const revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        revealObserver.unobserve(entry.target);
      });
    },
    { threshold: 0.12, rootMargin: "0px 0px -6% 0px" }
  );
  revealItems.forEach((item) => revealObserver.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

/* The overlay's session timer: counts while listening, holds once the text
   is being finished, and clears between runs. */
function overlayClock(windowEl) {
  const label = windowEl ? windowEl.querySelector(".overlay-time") : null;
  let started = 0;
  let interval = null;
  const render = (seconds) => {
    if (label) label.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
  };
  return {
    update(state) {
      if (state === "typing") {
        if (interval) return;
        started = performance.now();
        render(0);
        interval = setInterval(() => render(Math.floor((performance.now() - started) / 1000)), 250);
        return;
      }
      if (interval) clearInterval(interval);
      interval = null;
      if (state !== "processing" && state !== "done") render(0);
    }
  };
}

/* Between the last word and the text landing, the app polishes it. */
const processingDelay = 850;

const heroText =
  "Hi Priya, the invoice for August is ready. I pushed the final copy to the shared folder this morning.";
const heroTarget = document.getElementById("hero-typed");
const heroSection = document.querySelector(".hero");
const heroWindow = document.querySelector(".hero-window");
const heroLive = document.getElementById("hero-live");
const heroClock = overlayClock(heroWindow);
let heroTimer = null;
let heroVisible = true;

function stopHero() {
  if (heroTimer) {
    clearTimeout(heroTimer);
    heroTimer = null;
  }
}

function setHeroChrome(state) {
  if (!heroWindow) return;
  heroWindow.classList.toggle("is-typing", state === "typing");
  heroWindow.classList.toggle("is-processing", state === "processing");
  heroWindow.classList.toggle("is-done", state === "done");
  heroWindow.classList.toggle("is-resetting", state === "resetting");
  heroClock.update(state);
}

function startHero() {
  if (!heroTarget) return;
  stopHero();

  if (reduceMotion) {
    heroTarget.textContent = heroText;
    heroTarget.classList.add("is-inserted");
    if (heroLive) heroLive.textContent = heroText;
    setHeroChrome("done");
    return;
  }

  heroTarget.textContent = "";
  heroTarget.classList.remove("is-inserted");
  if (heroLive) heroLive.textContent = "";
  setHeroChrome("typing");

  const words = heroText.split(" ");
  let wordIndex = 0;

  const type = () => {
    if (!heroVisible) return;

    const word = words[wordIndex];
    if (heroLive) {
      heroLive.textContent = wordIndex === 0 ? word : `${heroLive.textContent} ${word}`;
    }
    wordIndex += 1;

    if (wordIndex >= words.length) {
      setHeroChrome("processing");
      heroTimer = setTimeout(() => {
        if (!heroVisible) return;
        heroTarget.textContent = heroText;
        heroTarget.classList.add("is-inserted");
        setHeroChrome("done");
        heroTimer = setTimeout(reset, 3600);
      }, processingDelay);
      return;
    }

    const punctuationPause = /[,.;:!?]$/.test(word) ? 220 : 0;
    heroTimer = setTimeout(type, 95 + Math.random() * 95 + punctuationPause);
  };

  const reset = () => {
    if (!heroVisible) return;
    setHeroChrome("resetting");
    heroTimer = setTimeout(() => {
      if (!heroVisible) return;
      heroTarget.textContent = "";
      heroTarget.classList.remove("is-inserted");
      if (heroLive) heroLive.textContent = "";
      wordIndex = 0;
      setHeroChrome("typing");
      heroTimer = setTimeout(type, 700);
    }, 360);
  };

  heroTimer = setTimeout(type, 700);
}

if (heroTarget) {
  if ("IntersectionObserver" in window) {
    const heroObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          heroVisible = entry.isIntersecting;
          if (heroVisible) startHero();
          else stopHero();
        });
      },
      { threshold: 0.15 }
    );
    heroObserver.observe(heroSection || heroTarget);
  } else {
    startHero();
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopHero();
    else if (heroVisible) startHero();
  });
}

const demoSteps = Array.from(document.querySelectorAll("[data-demo-step]"));
const demoTargets = Array.from(document.querySelectorAll("[data-pane]"));
const demoTabs = Array.from(document.querySelectorAll("[data-demo-tab]"));
const demoTitle = document.getElementById("demo-window-title");
const demoWindow = document.querySelector(".demo-window");
const demoLive = document.getElementById("demo-live");
const demoOverlayIcon = document.getElementById("demo-overlay-icon");
const demoIcons = ["slack", "cursor", "notes", "mail"];
const demoClock = overlayClock(demoWindow);
const demoStage = document.querySelector(".demo-stage");
const demoTitles = ["Slack", "Cursor", "Notes", "Mail"];
const mobileDemo = window.matchMedia("(max-width: 900px)");
let demoIndex = -1;
let demoTimer = null;
let demoVisible = false;
let demoActiveTyping = false;

function stopDemoTyping() {
  if (demoTimer) {
    clearTimeout(demoTimer);
    demoTimer = null;
  }
  demoActiveTyping = false;
}

function setDemoChrome(state) {
  if (!demoWindow) return;
  demoWindow.classList.toggle("is-typing", state === "typing");
  demoWindow.classList.toggle("is-processing", state === "processing");
  demoWindow.classList.toggle("is-done", state === "done");
  demoClock.update(state);
}

// An "@Name" in the result shows as a Slack mention.
function fillTarget(target, text) {
  target.textContent = "";
  text.split(/(@[A-Z][a-z]+)/).forEach((part) => {
    if (!part) return;
    if (part.startsWith("@")) {
      const mention = document.createElement("span");
      mention.className = "mention";
      mention.textContent = part;
      target.append(mention);
    } else {
      target.append(part);
    }
  });
}

function typeInto(target, text, options = {}) {
  if (!target) return;
  stopDemoTyping();
  setDemoChrome("typing");
  target.textContent = "";
  target.classList.remove("is-inserted");
  if (demoLive) demoLive.textContent = "";

  const spoken = options.instruction || target.dataset.spoken || text;

  if (reduceMotion) {
    fillTarget(target, text);
    target.classList.add("is-inserted");
    if (demoLive) demoLive.textContent = spoken;
    setDemoChrome("done");
    return;
  }

  const words = spoken.split(" ");
  let wordIndex = 0;
  demoActiveTyping = true;

  const tick = () => {
    if (!demoVisible) {
      demoActiveTyping = false;
      return;
    }

    const word = words[wordIndex];
    if (demoLive) {
      demoLive.textContent = wordIndex === 0 ? word : `${demoLive.textContent} ${word}`;
    }
    wordIndex += 1;

    if (wordIndex >= words.length) {
      setDemoChrome("processing");
      demoTimer = setTimeout(() => {
        demoActiveTyping = false;
        fillTarget(target, text);
        target.classList.add("is-inserted");
        setDemoChrome("done");
      }, processingDelay);
      return;
    }

    const punctuationPause = /[,.;:!?]$/.test(word) ? 220 : 0;
    demoTimer = setTimeout(tick, 95 + Math.random() * 95 + punctuationPause);
  };

  demoTimer = setTimeout(tick, 650);
}

function runEditDemo(pane) {
  const original = pane.querySelector(".edit-original");
  const result = pane.querySelector(".edit-result");
  if (!original || !result) return;

  stopDemoTyping();
  setDemoChrome("typing");
  original.classList.remove("is-replaced");
  original.classList.add("is-selected");
  result.classList.remove("is-inserted");
  if (demoLive) demoLive.textContent = "";

  const spoken = pane.dataset.instruction || "Make it shorter.";

  if (reduceMotion) {
    if (demoLive) demoLive.textContent = spoken;
    original.classList.add("is-replaced");
    original.classList.remove("is-selected");
    result.classList.add("is-inserted");
    setDemoChrome("done");
    return;
  }

  const words = spoken.split(" ");
  let wordIndex = 0;
  demoActiveTyping = true;

  const tick = () => {
    if (!demoVisible) {
      demoActiveTyping = false;
      return;
    }

    const word = words[wordIndex];
    if (demoLive) {
      demoLive.textContent = wordIndex === 0 ? word : `${demoLive.textContent} ${word}`;
    }
    wordIndex += 1;

    if (wordIndex >= words.length) {
      setDemoChrome("processing");
      demoTimer = setTimeout(() => {
        demoActiveTyping = false;
        original.classList.add("is-replaced");
        original.classList.remove("is-selected");
        result.classList.add("is-inserted");
        setDemoChrome("done");
      }, processingDelay);
      return;
    }

    const punctuationPause = /[,.;:!?]$/.test(word) ? 220 : 0;
    demoTimer = setTimeout(tick, 95 + Math.random() * 95 + punctuationPause);
  };

  demoTimer = setTimeout(tick, 650);
}

function startActiveDemoTyping() {
  if (demoIndex < 0) return;
  const pane = demoTargets[demoIndex];
  if (!pane) return;

  const mode = pane.dataset.mode || "dictate";
  if (mode === "edit") {
    runEditDemo(pane);
    return;
  }

  const target = pane.querySelector(".typed-target");
  if (!target) return;

  if (mode === "generate") {
    typeInto(target, pane.dataset.result || "", {
      instruction: pane.dataset.instruction || ""
    });
    return;
  }

  typeInto(target, target.dataset.text || "");
}

function setDemoStep(nextIndex, options = {}) {
  if (!demoSteps[nextIndex]) return;
  const type = options.type ?? demoVisible;

  if (nextIndex === demoIndex) {
    if (type && !demoActiveTyping) {
      const activePane = demoTargets[demoIndex];
      const target = activePane ? activePane.querySelector(".typed-target") : null;
      if (target && !target.textContent) startActiveDemoTyping();
    }
    return;
  }

  demoIndex = nextIndex;
  stopDemoTyping();
  setDemoChrome("idle");

  demoSteps.forEach((step, index) => {
    step.classList.toggle("is-active", index === nextIndex);
  });

  demoTargets.forEach((pane, index) => {
    const active = index === nextIndex;
    pane.classList.toggle("is-active", active);

    const target = pane.querySelector(".typed-target");
    if (target) {
      target.textContent = "";
      target.classList.remove("is-inserted");
    }

    const original = pane.querySelector(".edit-original");
    const result = pane.querySelector(".edit-result");
    if (original) original.classList.remove("is-selected", "is-replaced");
    if (result) result.classList.remove("is-inserted");

    if (active && pane.dataset.mode === "edit" && original) {
      original.classList.add("is-selected");
    }
  });

  if (demoLive) demoLive.textContent = "";
  if (demoOverlayIcon) demoOverlayIcon.dataset.app = demoIcons[nextIndex] || "";

  demoTabs.forEach((tab, index) => {
    const active = index === nextIndex;
    tab.classList.toggle("is-active", active);
    tab.setAttribute("aria-selected", active ? "true" : "false");
  });

  if (demoTitle) demoTitle.textContent = demoTitles[nextIndex] || "";

  if (type) startActiveDemoTyping();
}

if (demoSteps.length) {
  setDemoStep(0, { type: false });

  if ("IntersectionObserver" in window && !reduceMotion) {
    const demoObserver = new IntersectionObserver(
      (entries) => {
        if (mobileDemo.matches) return;
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          setDemoStep(Number(entry.target.dataset.demoStep));
        });
      },
      { threshold: 0, rootMargin: "-44% 0px -44% 0px" }
    );
    demoSteps.forEach((step) => demoObserver.observe(step));

    if (demoStage) {
      const stageObserver = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            demoVisible = entry.isIntersecting;
            if (demoVisible) {
              if (!demoActiveTyping) startActiveDemoTyping();
            } else {
              stopDemoTyping();
              setDemoChrome("idle");
            }
          });
        },
        { threshold: 0.25 }
      );
      stageObserver.observe(demoStage);
    } else {
      demoVisible = true;
    }
  } else {
    demoVisible = true;
    startActiveDemoTyping();
  }

  demoTabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const index = Number(tab.dataset.demoTab);
      if (index === demoIndex) {
        startActiveDemoTyping();
      } else {
        setDemoStep(index, { type: true });
      }

      if (!mobileDemo.matches) return;
      const stage = document.querySelector(".demo-stage");
      if (!stage) return;
      const top = stage.getBoundingClientRect().top + window.scrollY - 70;
      window.scrollTo({ top, behavior: reduceMotion ? "auto" : "smooth" });
    });
  });
}

/* Launch film. The link works on its own (it opens the MP4); with a dialog it
   plays in place, with sound, and phones in portrait get the 4:5 cut. */
const film = document.getElementById("film");
const filmVideo = document.getElementById("film-video");
const filmOpen = document.querySelector("[data-film-open]");
if (film && filmVideo && filmOpen && typeof film.showModal === "function") {
  const portrait = window.matchMedia("(max-width: 720px) and (orientation: portrait)");
  const closeFilm = () => {
    filmVideo.pause();
    if (film.open) film.close();
  };
  filmOpen.addEventListener("click", (event) => {
    event.preventDefault();
    const tall = portrait.matches;
    const src = tall ? "assets/film/quietspeech-film-feed.mp4" : "assets/film/quietspeech-film-720.mp4";
    film.classList.toggle("is-tall", tall);
    if (!filmVideo.src.endsWith(src)) {
      filmVideo.poster = tall ? "assets/film/poster-feed.jpg" : "assets/film/poster-720.jpg";
      filmVideo.src = src;
    }
    film.showModal();
    filmVideo.play().catch(() => {});
  });
  film.querySelector("[data-film-close]").addEventListener("click", closeFilm);
  film.addEventListener("click", (event) => {
    if (event.target === film) closeFilm();
  });
  film.addEventListener("close", () => filmVideo.pause());
}
