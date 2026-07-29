// ponytail: Keep one empty URL until a signed, notarized public build exists; replace it when distribution is ready.
const MAC_DOWNLOAD_URL = "";
const contentStore = globalThis.ONEUL_HOME_CONTENT;

function clamp(value) {
  return Math.min(Math.max(value, 0), 1);
}

function smoothstep(value) {
  const normalized = clamp(value);
  return normalized * normalized * (3 - 2 * normalized);
}

function range(progress, start, end) {
  return smoothstep((progress - start) / (end - start));
}

function visitorPlatform() {
  const userAgent = navigator.userAgent || "";
  const platform = navigator.userAgentData?.platform || navigator.platform || "";
  const ipad = /iPad/i.test(userAgent) || (platform === "MacIntel" && navigator.maxTouchPoints > 1);

  if (ipad) return "ipad";
  if (/iPhone|iPod/i.test(userAgent)) return "iphone";
  if (/Mac/i.test(platform) || /Macintosh/i.test(userAgent)) return "mac";
  if (/Android/i.test(userAgent)) return "android";
  if (/Win/i.test(platform) || /Windows/i.test(userAgent)) return "windows";
  return "other";
}

function resolveLocale() {
  try {
    const saved = globalThis.localStorage?.getItem("oneul-locale");
    if (saved && contentStore?.locales?.[saved]) return saved;
  } catch {
    // Storage can be blocked; Korean remains the stable default.
  }
  return contentStore?.defaultLocale || "ko";
}

let activeLocale = resolveLocale();
const platform = visitorPlatform();

function localeContent(locale = activeLocale) {
  return contentStore?.locales?.[locale] || contentStore?.locales?.ko;
}

function setMeta(selector, value) {
  const element = document.querySelector?.(selector);
  if (element && value) element.setAttribute("content", value);
}

function applyPlatformCopy(locale = activeLocale) {
  const strings = localeContent(locale)?.platform;
  if (!strings) return;

  const ctas = document.querySelectorAll?.("[data-platform-cta]") || [];
  const platformNote = document.querySelector?.("[data-platform-note]");
  const macStatus = document.querySelector?.("[data-mac-status]");
  let label = strings.apple;
  let href = "#devices";
  let unavailable = false;

  if (platform === "mac") {
    if (MAC_DOWNLOAD_URL) {
      label = strings.macDownload;
      href = MAC_DOWNLOAD_URL;
      if (platformNote) platformNote.textContent = strings.macRequirements;
      if (macStatus) macStatus.textContent = strings.macReady;
    } else {
      label = strings.macRelease;
      unavailable = true;
      if (platformNote) platformNote.textContent = strings.macPending;
    }
  } else if (platform === "iphone" || platform === "ipad") {
    if (platformNote) platformNote.textContent = strings.appleDevices;
  } else {
    label = strings.macVersion;
    if (platformNote) platformNote.textContent = strings.appleOnly;
  }

  for (const cta of ctas) {
    cta.textContent = label;
    cta.href = href;
    cta.classList.toggle("is-unavailable", unavailable);
    if (MAC_DOWNLOAD_URL && platform === "mac") cta.setAttribute("download", "");
    else cta.removeAttribute?.("download");
  }
}

function applyLocale(locale, persist = false) {
  const content = localeContent(locale);
  if (!content) return;
  activeLocale = locale;

  if (document.documentElement) document.documentElement.lang = locale === "ko" ? "ko-KR" : "en";
  if (content.meta?.title) document.title = content.meta.title;
  setMeta('meta[name="description"]', content.meta?.description);
  setMeta('meta[property="og:title"]', content.meta?.title);
  setMeta('meta[property="og:description"]', content.meta?.description);
  setMeta('meta[property="og:locale"]', locale === "ko" ? "ko_KR" : "en_US");
  setMeta('meta[name="twitter:title"]', content.meta?.title);
  setMeta('meta[name="twitter:description"]', content.meta?.description);

  for (const element of document.querySelectorAll?.("[data-copy]") || []) {
    const value = content.copy?.[element.dataset.copy];
    if (value !== undefined) element.textContent = value;
  }
  for (const element of document.querySelectorAll?.("[data-copy-html]") || []) {
    const value = content.copy?.[element.dataset.copyHtml];
    if (value !== undefined) element.innerHTML = value;
  }
  for (const button of document.querySelectorAll?.("[data-locale]") || []) {
    button.setAttribute("aria-pressed", String(button.dataset.locale === locale));
  }

  applyPlatformCopy(locale);
  if (persist) {
    try {
      globalThis.localStorage?.setItem("oneul-locale", locale);
    } catch {
      // Language still changes for this page view when storage is blocked.
    }
  }
}

applyLocale(activeLocale);

for (const button of document.querySelectorAll?.("[data-locale]") || []) {
  button.addEventListener("click", () => {
    applyLocale(button.dataset.locale, true);
    button.closest?.(".mobile-menu")?.removeAttribute("open");
  });
}

const mobileMenu = document.querySelector?.(".mobile-menu");
for (const link of mobileMenu?.querySelectorAll?.("a") || []) {
  link.addEventListener("click", () => mobileMenu.removeAttribute("open"));
}

function heroFrame(progress) {
  const value = clamp(progress);
  const handoff = range(value, 0.28, 0.96);
  const watchExit = range(value, 0.16, 0.62);
  const cueExit = range(value, 0.04, 0.28);

  return {
    progress: value,
    copyOpacity: 1 - handoff,
    copyX: -44 * handoff,
    copyY: -18 * handoff,
    copyScale: 1 - 0.025 * handoff,
    productX: -38 * handoff,
    productY: -34 * handoff,
    productScale: 1 + 0.14 * handoff,
    phoneRotate: 2 * (1 - handoff),
    phoneScale: 1 + 0.035 * handoff,
    watchOpacity: 1 - watchExit,
    watchX: 56 * watchExit,
    watchY: 30 * watchExit,
    watchScale: 1 - 0.12 * watchExit,
    railOpacity: 1 - 0.68 * handoff,
    railRotate: -7 + 7 * handoff,
    railScale: 1 + 1.35 * handoff,
    cueOpacity: 1 - cueExit,
  };
}

function flowFrame(progress) {
  const value = clamp(progress);
  const enter = range(value, 0.02, 0.2);
  const leave = range(value, 0.82, 0.98);
  const presence = enter * (1 - leave);

  return {
    progress: value,
    opacity: 0.38 + 0.62 * presence,
    y: 32 * (1 - enter) - 18 * leave,
    visualY: 42 * (1 - enter) - 22 * leave,
    scale: 0.975 + 0.025 * enter - 0.012 * leave,
    barScale: 0.72 + 0.28 * enter,
  };
}

function storyFrame(progress, stepCount) {
  const count = Math.max(1, stepCount);
  const value = clamp(progress);
  const phase = value * (count - 1);
  const current = Math.min(count - 1, Math.floor(phase));
  const local = phase - current;
  const blend = current === count - 1 ? 0 : range(local, 0.2, 0.8);
  const copyOut = 1 - range(local, 0.12, 0.34);
  const copyIn = range(local, 0.68, 0.9);
  const tail = range(value, 0.95, 1);
  const steps = Array.from({ length: count }, () => ({
    opacity: 0,
    copyOpacity: 0,
    copyY: 16,
    productY: 18,
    productScale: 0.985,
    productRotate: 0,
  }));

  steps[current] = {
    opacity: 1 - blend,
    copyOpacity: (current === count - 1 ? 1 : copyOut) * (1 - tail),
    copyY: -12 * (1 - copyOut),
    productY: -22 * blend,
    productScale: 1 - 0.025 * blend,
    productRotate: -1.5 * blend,
  };

  if (current < count - 1) {
    steps[current + 1] = {
      opacity: blend,
      copyOpacity: copyIn,
      copyY: 14 * (1 - copyIn),
      productY: 28 * (1 - blend),
      productScale: 0.975 + 0.025 * blend,
      productRotate: 1.5 * (1 - blend),
    };
  }

  return {
    progress: value,
    stageOpacity: 1 - tail,
    stageY: -24 * tail,
    stageScale: 1 - 0.02 * tail,
    auraScale: 0.92 + 0.12 * Math.sin(value * Math.PI),
    steps,
  };
}

function schoolFrame(progress, stepCount = 3) {
  const frame = storyFrame(progress, stepCount);
  const value = frame.progress;
  const timetableBuild = range(value, 0.28, 0.58);

  return {
    ...frame,
    stageY: -16 * range(value, 0.9, 1),
    stageRotate: 5 * (1 - range(value, 0, 0.24)),
    stageScale: 0.97 + 0.03 * range(value, 0, 0.24),
    selector: frame.steps[0],
    timetable: frame.steps[1],
    meal: frame.steps[2],
    classOpacity: 0.35 + 0.65 * timetableBuild,
  };
}

function deviceFrame(progress, stepCount = 3) {
  const frame = storyFrame(progress, stepCount);
  const value = frame.progress;
  const phoneState = frame.steps[0].opacity;
  const watchState = frame.steps[1].opacity;
  const macState = frame.steps[2].opacity;

  return {
    ...frame,
    macOpacity: 0.42 + 0.58 * macState + 0.14 * frame.steps[0].opacity,
    macX: 16 * (1 - macState),
    macY: 30 * (1 - macState),
    macScale: 0.78 + 0.22 * macState + 0.05 * phoneState,
    macRotate: 8 * (1 - macState),
    phoneOpacity: 0.18 + 0.82 * phoneState + 0.22 * watchState,
    phoneX: 46 * phoneState - 18 * macState,
    phoneY: -12 * phoneState + 36 * macState,
    phoneScale: 0.78 + 0.34 * phoneState,
    phoneRotate: -8 + 5 * value,
    watchOpacity: 0.18 + 0.82 * watchState + 0.14 * macState,
    watchX: -32 * watchState + 16 * macState,
    watchY: 26 * phoneState - 18 * watchState,
    watchScale: 0.76 + 0.38 * watchState,
    watchRotate: 7 - 5 * value,
    auraOpacity: 0.42 + 0.28 * Math.sin(value * Math.PI),
    auraScale: 0.88 + 0.18 * range(value, 0.1, 0.9),
  };
}

function finalFrame(progress) {
  const value = clamp(progress);
  const assemble = range(value, 0.08, 0.72);
  return {
    progress: value,
    spread: 1 - assemble,
    pieceOpacity: 1 - 0.9 * assemble,
    iconScale: 0.78 + 0.22 * assemble,
    atmosphereScale: 0.92 + 0.12 * assemble,
  };
}

const reducedMotionMedia = globalThis.matchMedia?.("(prefers-reduced-motion: reduce)");
const supportsScrollMotion = !(reducedMotionMedia?.matches ?? false) && "requestAnimationFrame" in globalThis;
const scrollPosition = () => globalThis.scrollY || document.documentElement?.scrollTop || 0;
const scrollMotionTasks = [];

function setNumber(element, name, value, unit = "") {
  element?.style?.setProperty(name, `${value.toFixed(3)}${unit}`);
}

function addPinnedScene({ root, sticky, count, frame, apply }) {
  if (!root || !sticky || !supportsScrollMotion) return;
  let start = 0;
  let distance = 1;
  let lastProgress = Number.NaN;

  scrollMotionTasks.push({
    measure() {
      const y = scrollPosition();
      const headerHeight = Number.parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue("--header-height"),
      ) || 0;
      start = root.getBoundingClientRect().top + y - headerHeight;
      distance = Math.max(root.offsetHeight - (sticky.clientHeight || globalThis.innerHeight || 1), 1);
      lastProgress = Number.NaN;
    },
    render() {
      const progress = clamp((scrollPosition() - start) / distance);
      if (progress === lastProgress) return;
      lastProgress = progress;
      apply(frame(progress, count));
    },
  });
}

const hero = document.querySelector?.("[data-hero-scene]");
const heroSticky = hero?.querySelector?.(".hero-sticky");
if (hero && heroSticky && supportsScrollMotion) {
  addPinnedScene({
    root: hero,
    sticky: heroSticky,
    count: 1,
    frame: heroFrame,
    apply(frame) {
      setNumber(hero, "--hero-copy-opacity", frame.copyOpacity);
      setNumber(hero, "--hero-copy-x", frame.copyX, "px");
      setNumber(hero, "--hero-copy-y", frame.copyY, "px");
      setNumber(hero, "--hero-copy-scale", frame.copyScale);
      setNumber(hero, "--hero-product-x", frame.productX, "px");
      setNumber(hero, "--hero-product-y", frame.productY, "px");
      setNumber(hero, "--hero-product-scale", frame.productScale);
      setNumber(hero, "--hero-phone-rotate", frame.phoneRotate, "deg");
      setNumber(hero, "--hero-phone-scale", frame.phoneScale);
      setNumber(hero, "--hero-watch-opacity", frame.watchOpacity);
      setNumber(hero, "--hero-watch-x", frame.watchX, "px");
      setNumber(hero, "--hero-watch-y", frame.watchY, "px");
      setNumber(hero, "--hero-watch-scale", frame.watchScale);
      setNumber(hero, "--hero-rail-opacity", frame.railOpacity);
      setNumber(hero, "--hero-rail-rotate", frame.railRotate, "deg");
      setNumber(hero, "--hero-rail-scale", frame.railScale);
      setNumber(hero, "--hero-cue-opacity", frame.cueOpacity);
    },
  });
  document.documentElement?.classList.add("hero-ready");
}

const story = document.querySelector?.("[data-scroll-story]");
const storySteps = story?.querySelectorAll?.("[data-story-step]") || [];
const storyProducts = story?.querySelectorAll?.("[data-story-product]") || [];
if (story && storySteps.length && storySteps.length === storyProducts.length && supportsScrollMotion) {
  addPinnedScene({
    root: story,
    sticky: story.querySelector(".story-visual-sticky"),
    count: storySteps.length,
    frame: storyFrame,
    apply(frame) {
      setNumber(story, "--story-progress", frame.progress);
      setNumber(story, "--story-stage-opacity", frame.stageOpacity);
      setNumber(story, "--story-stage-y", frame.stageY, "px");
      setNumber(story, "--story-stage-scale", frame.stageScale);
      setNumber(story, "--story-aura-scale", frame.auraScale);
      for (let index = 0; index < storySteps.length; index += 1) {
        const state = frame.steps[index];
        setNumber(storySteps[index], "--step-opacity", state.copyOpacity);
        setNumber(storySteps[index], "--copy-y", state.copyY, "px");
        setNumber(storyProducts[index], "--product-opacity", state.opacity);
        setNumber(storyProducts[index], "--product-y", state.productY, "px");
        setNumber(storyProducts[index], "--product-scale", state.productScale);
        setNumber(storyProducts[index], "--product-rotate", state.productRotate, "deg");
      }
    },
  });
  document.documentElement?.classList.add("story-ready");
}

const school = document.querySelector?.("[data-school-story]");
const schoolSteps = school?.querySelectorAll?.("[data-school-step]") || [];
if (school && schoolSteps.length && supportsScrollMotion) {
  addPinnedScene({
    root: school.querySelector(".school-shell"),
    sticky: school.querySelector(".school-visual-sticky"),
    count: schoolSteps.length,
    frame: schoolFrame,
    apply(frame) {
      const root = school.querySelector(".school-shell");
      setNumber(root, "--scene-progress", frame.progress);
      setNumber(root, "--school-stage-y", frame.stageY, "px");
      setNumber(root, "--school-stage-rotate", frame.stageRotate, "deg");
      setNumber(root, "--school-stage-scale", frame.stageScale);
      setNumber(root, "--school-class-opacity", frame.classOpacity);
      for (let index = 0; index < schoolSteps.length; index += 1) {
        const state = frame.steps[index];
        setNumber(schoolSteps[index], "--step-opacity", state.copyOpacity);
        setNumber(schoolSteps[index], "--copy-y", state.copyY, "px");
      }
      for (const [name, state] of [["selector", frame.selector], ["timetable", frame.timetable], ["meal", frame.meal]]) {
        setNumber(root, `--school-${name}-opacity`, state.opacity);
        setNumber(root, `--school-${name}-x`, state.productRotate * 8, "px");
        setNumber(root, `--school-${name}-y`, state.productY, "px");
        setNumber(root, `--school-${name}-scale`, state.productScale);
      }
    },
  });
  document.documentElement?.classList.add("school-ready");
}

const devices = document.querySelector?.("[data-device-story]");
const deviceSteps = devices?.querySelectorAll?.("[data-device-step]") || [];
if (devices && deviceSteps.length && supportsScrollMotion) {
  addPinnedScene({
    root: devices.querySelector(".device-story-shell"),
    sticky: devices.querySelector(".device-visual-sticky"),
    count: deviceSteps.length,
    frame: deviceFrame,
    apply(frame) {
      const root = devices.querySelector(".device-story-shell");
      setNumber(root, "--scene-progress", frame.progress);
      for (let index = 0; index < deviceSteps.length; index += 1) {
        const state = frame.steps[index];
        setNumber(deviceSteps[index], "--step-opacity", state.copyOpacity);
        setNumber(deviceSteps[index], "--copy-y", state.copyY, "px");
      }
      for (const name of ["mac", "phone", "watch"]) {
        setNumber(root, `--device-${name}-opacity`, frame[`${name}Opacity`]);
        setNumber(root, `--device-${name}-x`, frame[`${name}X`], "px");
        setNumber(root, `--device-${name}-y`, frame[`${name}Y`], "px");
        setNumber(root, `--device-${name}-scale`, frame[`${name}Scale`]);
        setNumber(root, `--device-${name}-rotate`, frame[`${name}Rotate`], "deg");
      }
      setNumber(root, "--device-aura-opacity", frame.auraOpacity);
      setNumber(root, "--device-aura-scale", frame.auraScale);
    },
  });
  document.documentElement?.classList.add("device-ready");
}

const flowSections = supportsScrollMotion
  ? Array.from(document.querySelectorAll?.('[data-flow-section]:not([data-flow-section="hero"])') || [])
  : [];
if (flowSections.length) {
  let viewportHeight = globalThis.innerHeight || 1;
  const entries = flowSections.map((element) => ({ element, top: 0, height: 1, lastProgress: Number.NaN }));
  scrollMotionTasks.push({
    measure() {
      const y = scrollPosition();
      viewportHeight = globalThis.innerHeight || 1;
      for (const entry of entries) {
        entry.top = entry.element.getBoundingClientRect().top + y;
        entry.height = Math.max(entry.element.offsetHeight, 1);
        entry.lastProgress = Number.NaN;
      }
    },
    render() {
      const y = scrollPosition();
      for (const entry of entries) {
        const progress = clamp((y + viewportHeight - entry.top) / (entry.height + viewportHeight));
        if (progress === entry.lastProgress) continue;
        entry.lastProgress = progress;
        const frame = flowFrame(progress);
        setNumber(entry.element, "--flow-opacity", frame.opacity);
        setNumber(entry.element, "--flow-y", frame.y, "px");
        setNumber(entry.element, "--flow-visual-y", frame.visualY, "px");
        setNumber(entry.element, "--flow-scale", frame.scale);
        setNumber(entry.element, "--flow-bar-scale", frame.barScale);
      }
    },
  });
  document.documentElement?.classList.add("flow-ready");
}

const finalScene = document.querySelector?.("[data-final-scene]");
const finalPieces = finalScene?.querySelectorAll?.(".reassembly > i") || [];
const piecePositions = [
  [-92, -52, -14], [-66, 64, 9], [-22, -88, -5], [6, 88, 4], [50, -72, 10], [86, 52, -8], [102, -18, 15],
];
if (finalScene && finalPieces.length && supportsScrollMotion) {
  let top = 0;
  let height = 1;
  let lastProgress = Number.NaN;
  scrollMotionTasks.push({
    measure() {
      const y = scrollPosition();
      top = finalScene.getBoundingClientRect().top + y;
      height = Math.max(finalScene.offsetHeight, 1);
      lastProgress = Number.NaN;
    },
    render() {
      const progress = clamp((scrollPosition() + (globalThis.innerHeight || 1) - top) / (height + (globalThis.innerHeight || 1) * 0.45));
      if (progress === lastProgress) return;
      lastProgress = progress;
      const frame = finalFrame(progress);
      setNumber(finalScene, "--final-piece-opacity", frame.pieceOpacity);
      setNumber(finalScene, "--final-icon-scale", frame.iconScale);
      setNumber(finalScene, "--final-atmosphere-scale", frame.atmosphereScale);
      for (let index = 0; index < finalPieces.length; index += 1) {
        const [x, y, rotation] = piecePositions[index];
        setNumber(finalPieces[index], "--piece-x", x * frame.spread, "px");
        setNumber(finalPieces[index], "--piece-y", y * frame.spread, "px");
        setNumber(finalPieces[index], "--piece-r", rotation * frame.spread, "deg");
      }
    },
  });
}

const siteHeader = document.querySelector?.("[data-site-header]");
const navLinks = Array.from(document.querySelectorAll?.('.nav-links a[href^="#"]') || []);
const navSections = navLinks.map((link) => ({ link, section: document.querySelector?.(link.getAttribute("href")), top: 0 }));
let navLastProgress = Number.NaN;
scrollMotionTasks.push({
  measure() {
    const y = scrollPosition();
    for (const entry of navSections) entry.top = (entry.section?.getBoundingClientRect().top || 0) + y;
  },
  render() {
    const y = scrollPosition();
    const pageDistance = Math.max((document.documentElement?.scrollHeight || 1) - (globalThis.innerHeight || 1), 1);
    const progress = clamp(y / pageDistance);
    if (progress !== navLastProgress) {
      navLastProgress = progress;
      setNumber(document.documentElement, "--page-progress", progress);
      siteHeader?.classList.toggle("is-compact", y > 20);
      hero?.classList.toggle("is-active", y < (hero?.offsetHeight || globalThis.innerHeight || 1));
    }
    const marker = y + (globalThis.innerHeight || 1) * 0.38;
    let current = null;
    for (const entry of navSections) if (entry.section && entry.top <= marker) current = entry;
    for (const entry of navSections) {
      if (entry === current) entry.link.setAttribute("aria-current", "true");
      else entry.link.removeAttribute("aria-current");
    }
  },
});

if (supportsScrollMotion) document.documentElement?.classList.add("motion-ready");
hero?.classList.add("is-active");

if (scrollMotionTasks.length && "requestAnimationFrame" in globalThis) {
  let ticking = false;
  let needsMeasure = false;

  const renderMotion = (measure = false) => {
    if (measure) for (const task of scrollMotionTasks) task.measure();
    for (const task of scrollMotionTasks) task.render();
  };

  const scheduleMotion = (measure = false) => {
    needsMeasure ||= measure;
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      renderMotion(needsMeasure);
      needsMeasure = false;
      ticking = false;
    });
  };

  renderMotion(true);
  globalThis.addEventListener("scroll", () => scheduleMotion(), { passive: true });
  globalThis.addEventListener("resize", () => scheduleMotion(true));
  globalThis.addEventListener("orientationchange", () => scheduleMotion(true));
  globalThis.addEventListener("pageshow", () => scheduleMotion(true));
  document.fonts?.ready?.then(() => scheduleMotion(true));

  if ("ResizeObserver" in globalThis) {
    const resizeObserver = new ResizeObserver(() => scheduleMotion(true));
    const main = document.querySelector?.("main");
    if (main) resizeObserver.observe(main);
  }
}
