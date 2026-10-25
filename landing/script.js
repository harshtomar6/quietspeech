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

const heroText =
  "Hi Priya, the invoice for August is ready. I pushed the final copy to the shared folder this morning.";
const heroTarget = document.getElementById("hero-typed");
const heroSection = document.querySelector(".hero");
const heroWindow = document.querySelector(".hero-window");
const heroLive = document.getElementById("hero-live");
const heroOverlayLabel = document.getElementById("hero-overlay-label");
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
  heroWindow.classList.toggle("is-done", state === "done");
  heroWindow.classList.toggle("is-resetting", state === "resetting");
  if (heroOverlayLabel) {
    heroOverlayLabel.textContent = state === "done" ? "Inserted" : "Listening";
  }
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
      heroTarget.textContent = heroText;
      heroTarget.classList.add("is-inserted");
      setHeroChrome("done");
      heroTimer = setTimeout(reset, 3600);
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
const demoOverlayLabel = demoWindow ? demoWindow.querySelector(".overlay-label") : null;
const demoLive = document.getElementById("demo-live");
const demoOverlayApp = document.getElementById("demo-overlay-app");
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

const demoLabels = {
  dictate: { active: "Listening", done: "Inserted" },
  edit: { active: "Editing", done: "Rewritten" },
  generate: { active: "Generating", done: "Draft inserted" }
};

function demoMode() {
  const pane = demoTargets[demoIndex];
  return pane?.dataset.mode || "dictate";
}

function setDemoChrome(state) {
  if (!demoWindow) return;
  const labels = demoLabels[demoMode()] || demoLabels.dictate;
  demoWindow.classList.toggle("is-typing", state === "typing");
  demoWindow.classList.toggle("is-done", state === "done");
  if (demoOverlayLabel) {
    demoOverlayLabel.textContent = state === "done" ? labels.done : labels.active;
  }
}

function typeInto(target, text, options = {}) {
  if (!target) return;
  stopDemoTyping();
  setDemoChrome("typing");
  target.textContent = "";
  target.classList.remove("is-inserted");
  if (demoLive) demoLive.textContent = "";

  const spoken = options.instruction || text;

  if (reduceMotion) {
    target.textContent = text;
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
      demoActiveTyping = false;
      target.textContent = text;
      target.classList.add("is-inserted");
      setDemoChrome("done");
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
      demoActiveTyping = false;
      original.classList.add("is-replaced");
      original.classList.remove("is-selected");
      result.classList.add("is-inserted");
      setDemoChrome("done");
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
  if (demoOverlayApp) demoOverlayApp.textContent = demoTitles[nextIndex] || "";

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
