// ponytail: Keep one empty URL until a signed, notarized public build exists; replace it when distribution is ready.
const MAC_DOWNLOAD_URL = "";
const APP_STORE_URL = {
  ko: "https://apps.apple.com/kr/app/oneul-calendar/id6788308943",
  en: "https://apps.apple.com/us/app/oneul-calendar/id6788308943",
};
const DOWNLOAD_PAGE_URL = "/download";
const contentStore = globalThis.ONEUL_HOME_CONTENT;
const pageName = document.body?.dataset?.page || "home";
const downloadDevices = new Set(["iphone", "ipad", "watch", "mac"]);

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

function requestedDownloadDevice() {
  try {
    const requested = new URLSearchParams(globalThis.location?.search || "").get("device");
    return downloadDevices.has(requested) ? requested : null;
  } catch {
    return null;
  }
}

function platformDownloadDevice() {
  return downloadDevices.has(platform) ? platform : "all";
}

let selectedDownloadDevice = requestedDownloadDevice() || platformDownloadDevice();

function localeContent(locale = activeLocale) {
  return contentStore?.locales?.[locale] || contentStore?.locales?.ko;
}

function appStoreUrl(locale = activeLocale) {
  return APP_STORE_URL[locale] || APP_STORE_URL.ko;
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
  const device = pageName === "download" ? selectedDownloadDevice : platformDownloadDevice();
  let label = strings.download;
  let href = DOWNLOAD_PAGE_URL;
  let directDownload = false;

  if (pageName === "download") {
    if (device === "iphone" || device === "ipad" || device === "watch") {
      label = strings.apple;
      href = appStoreUrl(locale);
      if (platformNote) platformNote.textContent = strings[device + "Ready"];
    } else if (device === "mac") {
      if (MAC_DOWNLOAD_URL) {
        label = strings.macDownload;
        href = MAC_DOWNLOAD_URL;
        directDownload = true;
        if (platformNote) platformNote.textContent = strings.macRequirements;
        if (macStatus) macStatus.textContent = strings.macReady;
      } else {
        label = strings.macRelease;
        href = "#mac-story";
        if (platformNote) platformNote.textContent = strings.macPending;
        if (macStatus) macStatus.textContent = strings.macPending;
      }
    } else {
      label = strings.macVersion;
      href = "#devices";
      if (platformNote) platformNote.textContent = strings.otherReady;
    }
  } else {
    if (device === "iphone") {
      label = strings.iphoneDownload;
      href = `${DOWNLOAD_PAGE_URL}?device=iphone`;
      if (platformNote) platformNote.textContent = strings.iphoneReady;
    } else if (device === "ipad") {
      label = strings.ipadDownload;
      href = `${DOWNLOAD_PAGE_URL}?device=ipad`;
      if (platformNote) platformNote.textContent = strings.ipadReady;
    } else if (device === "mac") {
      label = strings.macRelease;
      href = `${DOWNLOAD_PAGE_URL}?device=mac`;
      if (platformNote) platformNote.textContent = strings.macPending;
      if (macStatus) macStatus.textContent = MAC_DOWNLOAD_URL ? strings.macReady : strings.macPending;
    } else {
      if (platformNote) platformNote.textContent = strings.appleOnly;
    }
  }

  for (const cta of ctas) {
    cta.textContent = label;
    cta.href = href;
    cta.classList.toggle("is-unavailable", false);
    if (directDownload) cta.setAttribute("download", "");
    else cta.removeAttribute?.("download");
  }
}

function renderDownloadSelection(locale = activeLocale) {
  if (pageName !== "download") return;
  const strings = localeContent(locale)?.platform;
  const root = document.querySelector?.("[data-download-hero]");
  const status = document.querySelector?.("[data-device-detected]");
  if (document.body?.dataset) document.body.dataset.selectedDevice = selectedDownloadDevice;
  if (root?.dataset) root.dataset.selectedDevice = selectedDownloadDevice;

  for (const button of document.querySelectorAll?.("[data-device-choice]") || []) {
    button.setAttribute("aria-pressed", String(button.dataset.deviceChoice === selectedDownloadDevice));
  }
  for (const card of document.querySelectorAll?.("[data-download-device]") || []) {
    const recommended = card.dataset.downloadDevice === selectedDownloadDevice;
    card.classList.toggle("is-recommended", recommended);
    const badge = card.querySelector?.(".download-recommended");
    if (badge) badge.hidden = !recommended;
  }
  if (status && strings) {
    if (selectedDownloadDevice === "mac") status.textContent = MAC_DOWNLOAD_URL ? strings.macRequirements : strings.macPending;
    else {
      const key = selectedDownloadDevice === "all" ? "otherReady" : selectedDownloadDevice + "Ready";
      status.textContent = strings[key] || strings.otherReady;
    }
  }
}

function selectDownloadDevice(device, updateUrl = false) {
  if (!downloadDevices.has(device)) return;
  selectedDownloadDevice = device;
  if (updateUrl && globalThis.history?.replaceState && globalThis.location) {
    const url = new URL(globalThis.location.href);
    url.searchParams.set("device", device);
    globalThis.history.replaceState(null, "", url);
  }
  renderDownloadSelection();
  applyPlatformCopy();
}

function applyLocale(locale, persist = false) {
  const content = localeContent(locale);
  if (!content) return;
  activeLocale = locale;
  const meta = pageName === "download" ? content.downloadMeta : content.meta;

  if (document.documentElement) document.documentElement.lang = locale === "ko" ? "ko-KR" : "en";
  if (meta?.title) document.title = meta.title;
  setMeta('meta[name="description"]', meta?.description);
  setMeta('meta[property="og:title"]', meta?.title);
  setMeta('meta[property="og:description"]', meta?.description);
  setMeta('meta[property="og:locale"]', locale === "ko" ? "ko_KR" : "en_US");
  setMeta('meta[name="twitter:title"]', meta?.title);
  setMeta('meta[name="twitter:description"]', meta?.description);

  for (const element of document.querySelectorAll?.("[data-copy]") || []) {
    const value = content.copy?.[element.dataset.copy];
    if (value !== undefined) element.textContent = value;
  }
  for (const element of document.querySelectorAll?.("[data-copy-html]") || []) {
    const value = content.copy?.[element.dataset.copyHtml];
    if (value !== undefined) element.innerHTML = value;
  }
  for (const element of document.querySelectorAll?.("[data-copy-aria]") || []) {
    const value = content.copy?.[element.dataset.copyAria];
    if (value !== undefined) element.setAttribute("aria-label", value);
  }
  for (const link of document.querySelectorAll?.("[data-app-store-link]") || []) link.href = appStoreUrl(locale);
  for (const button of document.querySelectorAll?.("[data-locale]") || []) {
    button.setAttribute("aria-pressed", String(button.dataset.locale === locale));
  }

  applyPlatformCopy(locale);
  renderDownloadSelection(locale);
  if (persist) {
    try {
      globalThis.localStorage?.setItem("oneul-locale", locale);
    } catch {
      // Language still changes for this page view when storage is blocked.
    }
  }
}

applyLocale(activeLocale);

for (const button of document.querySelectorAll?.("[data-device-choice]") || []) {
  button.addEventListener("click", () => selectDownloadDevice(button.dataset.deviceChoice, true));
}

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
  const productReveal = range(value, 0.06, 0.34);
  const pillReveal = range(value, 0.08, 0.24);
  const pillHandoff = range(value, 0.28, 0.7);
  const handoff = range(value, 0.46, 0.94);
  const watchExit = range(value, 0.34, 0.66);
  const cueExit = range(value, 0.02, 0.16);

  return {
    progress: value,
    copyOpacity: 1 - handoff,
    copyX: -64 * handoff,
    copyY: -28 * handoff,
    copyScale: 1 - 0.04 * handoff,
    productX: -52 * handoff,
    productY: -52 * handoff - 12 * productReveal,
    productScale: 0.94 + 0.1 * productReveal + 0.28 * handoff,
    phoneRotate: 5 * (1 - productReveal) - 3 * handoff,
    phoneScale: 0.96 + 0.08 * productReveal + 0.16 * handoff,
    watchOpacity: 1 - watchExit,
    watchX: 82 * watchExit,
    watchY: 46 * watchExit,
    watchScale: 1 - 0.18 * watchExit,
    railOpacity: 1 - 0.78 * handoff,
    railRotate: -10 + 10 * productReveal,
    railScale: 0.72 + 0.38 * productReveal + 1.7 * handoff,
    cueOpacity: 1 - cueExit,
    pillOpacity: pillReveal * (1 - range(value, 0.64, 0.8)),
    pillX: -42 + 128 * pillReveal + 150 * pillHandoff,
    pillY: 40 - 82 * pillReveal + 180 * pillHandoff,
    pillScale: 0.88 + 0.12 * pillReveal - 0.2 * pillHandoff,
    atmosphereOpacity: 0.5 + 0.28 * productReveal - 0.18 * handoff,
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
  const phase = value * count;
  const current = Math.min(count - 1, Math.floor(phase));
  const local = Math.min(phase - current, 1);
  const blend = current === count - 1 ? 0 : range(local, 0.58, 0.92);
  const tail = range(value, 0.975, 1);
  const steps = Array.from({ length: count }, () => ({
    opacity: 0,
    copyOpacity: 0,
    copyY: 22,
    productY: 24,
    productScale: 0.975,
    productRotate: 0,
  }));

  steps[current] = {
    opacity: 1 - blend,
    copyOpacity: 1 - tail,
    copyY: -10 * blend,
    productY: -34 * blend,
    productScale: 1 - 0.035 * blend,
    productRotate: -2.2 * blend,
  };

  if (current < count - 1) {
    steps[current + 1] = {
      opacity: blend,
      copyOpacity: blend,
      copyY: 22 * (1 - blend),
      productY: 36 * (1 - blend),
      productScale: 0.965 + 0.035 * blend,
      productRotate: 2.2 * (1 - blend),
    };
  }

  return {
    progress: value,
    current,
    local,
    blend,
    stageOpacity: 1 - tail,
    stageY: -36 * tail,
    stageScale: 1 - 0.035 * tail,
    auraScale: 0.9 + 0.16 * Math.sin(value * Math.PI),
    steps,
  };
}

function commandFrame(progress, stepCount = 8) {
  const frame = storyFrame(progress, stepCount);
  const value = frame.progress;
  const type = range(value, 0.025, 0.145);
  const tokensIn = range(value, 0.11, 0.2);
  const tokensOut = range(value, 0.25, 0.34);
  const inputOut = range(value, 0.25, 0.36);
  const reviewIn = range(value, 0.25, 0.36);
  const reviewOut = range(value, 0.54, 0.64);
  const timelineIn = range(value, 0.55, 0.67);
  const flight = range(value, 0.51, 0.65);
  const ambiguity = range(value, 0.36, 0.48) * (1 - range(value, 0.49, 0.55));
  const tail = range(value, 0.94, 1);

  return {
    ...frame,
    stageOpacity: 1 - 0.85 * tail,
    stageX: 26 * range(value, 0.78, 0.96),
    stageY: -32 * tail,
    stageScale: 1 - 0.06 * tail,
    phoneX: -34 * range(value, 0.7, 0.9),
    phoneY: -18 * range(value, 0.62, 0.92),
    phoneZ: 90 * range(value, 0.72, 0.9),
    phoneRotateY: -8 + 8 * range(value, 0.08, 0.32) - 4 * range(value, 0.78, 0.94),
    phoneRotateZ: 2.5 - 2.5 * range(value, 0.08, 0.32),
    phoneScale: 0.9 + 0.1 * range(value, 0.06, 0.2) + 0.18 * range(value, 0.72, 0.9),
    inputOpacity: 1 - inputOut,
    inputY: -18 * inputOut,
    inputScale: 1 - 0.025 * inputOut,
    reviewOpacity: reviewIn * (1 - reviewOut),
    reviewY: 22 * (1 - reviewIn) - 16 * reviewOut,
    reviewScale: 0.975 + 0.025 * reviewIn - 0.02 * reviewOut,
    timelineOpacity: timelineIn,
    timelineY: 28 * (1 - timelineIn),
    timelineScale: 0.96 + 0.04 * timelineIn + 0.12 * range(value, 0.78, 0.92),
    typeProgress: type,
    typeComplete: range(value, 0.145, 0.18),
    tokenOpacity: tokensIn * (1 - tokensOut),
    tokenY: 14 * (1 - tokensIn) - 10 * tokensOut,
    tokenScale: 0.94 + 0.06 * tokensIn,
    resultY: 18 * (1 - reviewIn),
    resultScale: 0.96 + 0.04 * reviewIn,
    ambiguityOpacity: ambiguity,
    ambiguityY: 12 * (1 - ambiguity),
    applyOpacity: 0.4 + 0.6 * range(value, 0.43, 0.53),
    voiceOpacity: range(value, 0.01, 0.08) * (1 - range(value, 0.14, 0.22)),
    voiceX: -54 + 74 * range(value, 0.01, 0.12),
    voiceY: 32 - 46 * range(value, 0.01, 0.12),
    voiceScale: 0.88 + 0.12 * range(value, 0.01, 0.12),
    flightOpacity: range(value, 0.49, 0.54) * (1 - range(value, 0.63, 0.68)),
    flightX: -118 + 154 * flight,
    flightY: 142 - 240 * flight,
    flightRotate: -9 + 9 * flight,
    flightScale: 0.78 + 0.22 * flight,
    orbitOpacity: 0.16 + 0.3 * Math.sin(value * Math.PI),
    orbitRotate: value * 185,
    orbitScale: 0.82 + 0.23 * range(value, 0.08, 0.72),
    redOpacity: 0.2 + 0.22 * (1 - value),
    redX: -32 * value,
    redScale: 0.9 + 0.18 * Math.sin(value * Math.PI),
    blueOpacity: 0.16 + 0.22 * value,
    blueX: 28 * value,
    blueScale: 0.92 + 0.16 * Math.sin(value * Math.PI),
    nowY: 45 + 35 * range(value, 0.69, 0.92),
  };
}

function schoolFrame(progress, stepCount = 5) {
  const frame = storyFrame(progress, stepCount);
  const value = frame.progress;
  const timetableBuild = range(value, 0.58, 0.82);

  return {
    ...frame,
    stageX: 24 * range(value, 0.84, 1),
    stageY: -22 * range(value, 0.9, 1),
    stageRotate: 5 * (1 - range(value, 0, 0.18)),
    stageRotateY: -7 + 7 * range(value, 0.02, 0.2),
    stageScale: 0.94 + 0.06 * range(value, 0, 0.2),
    auraOpacity: 0.28 + 0.26 * Math.sin(value * Math.PI),
    auraScale: 0.9 + 0.2 * range(value, 0.1, 0.85),
    search: frame.steps[0],
    class: frame.steps[1],
    elective: frame.steps[2],
    timetable: frame.steps[3],
    meal: frame.steps[4],
    classOpacity: 0.35 + 0.65 * timetableBuild,
  };
}

function rhythmFrame(progress, stepCount = 5) {
  const frame = storyFrame(progress, stepCount);
  const value = frame.progress;
  const collapse = range(value, 0.19, 0.39);
  const manipulate = range(value, 0.38, 0.56);
  const live = range(value, 0.58, 0.72) * (1 - range(value, 0.82, 0.94));
  const evening = range(value, 0.78, 1);

  return {
    ...frame,
    phoneX: -30 * live + 16 * evening,
    phoneY: -18 * collapse + 24 * evening,
    phoneScale: 0.92 + 0.12 * collapse - 0.08 * live - 0.05 * evening,
    phoneRotateY: -6 + 6 * collapse - 4 * evening,
    phoneRotateZ: 2 - 2 * collapse,
    chromeOpacity: 1 - 0.92 * collapse,
    chromeY: -42 * collapse,
    chromeScale: 1 - 0.22 * collapse,
    gridTop: 252 - 128 * collapse,
    gridY: -26 * collapse + 18 * evening,
    gridScale: 1 + 0.035 * manipulate,
    eventOpacity: 1 - 0.55 * evening,
    eventX: 38 * manipulate,
    eventY: 34 * manipulate,
    eventScaleY: 1 + 0.4 * range(value, 0.46, 0.56),
    handleOpacity: range(value, 0.4, 0.48) * (1 - range(value, 0.56, 0.62)),
    nowY: 30 + 56 * value,
    liveOpacity: live,
    liveX: 70 * (1 - live),
    liveY: 34 * (1 - live),
    liveScale: 0.9 + 0.1 * live,
    morningOpacity: 1 - range(value, 0.28, 0.5),
    dayOpacity: 0.35 + 0.65 * range(value, 0.18, 0.48) - 0.5 * evening,
    eveningOpacity: evening,
    clockOpacity: 0.1 + 0.12 * Math.sin(value * Math.PI),
    clockY: -32 * value,
  };
}

function deviceFrame(progress, stepCount = 5) {
  const frame = storyFrame(progress, stepCount);
  const value = frame.progress;
  const phoneState = frame.steps[0].opacity;
  const tabletState = frame.steps[1].opacity;
  const liveState = frame.steps[2].opacity;
  const watchState = frame.steps[3].opacity;
  const macState = frame.steps[4].opacity;

  return {
    ...frame,
    macOpacity: 0.12 + 0.88 * macState,
    macX: 24 * (1 - macState),
    macY: 42 * (1 - macState),
    macScale: 0.72 + 0.28 * macState,
    macRotate: 9 * (1 - macState),
    macEventOpacity: range(value, 0.84, 0.96),
    macEventY: 12 * (1 - range(value, 0.84, 0.96)),
    phoneOpacity: 0.08 + 0.92 * phoneState + 0.18 * liveState,
    phoneX: 58 * phoneState - 26 * liveState,
    phoneY: -14 * phoneState + 30 * (1 - phoneState),
    phoneScale: 0.72 + 0.42 * phoneState,
    phoneRotate: -9 + 7 * value,
    tabletOpacity: tabletState,
    tabletX: 34 * (1 - tabletState),
    tabletY: 28 * (1 - tabletState),
    tabletScale: 0.78 + 0.22 * tabletState,
    tabletRotate: 5 * (1 - tabletState),
    liveOpacity: liveState,
    liveX: 48 * (1 - liveState),
    liveY: 26 * (1 - liveState),
    liveScale: 0.84 + 0.16 * liveState,
    islandOpacity: liveState,
    islandX: -26 * liveState,
    islandY: -52 + 52 * liveState,
    islandScale: 0.72 + 0.28 * liveState,
    watchOpacity: 0.08 + 0.92 * watchState,
    watchX: -42 * watchState + 18 * macState,
    watchY: 28 * (1 - watchState) - 16 * watchState,
    watchScale: 0.72 + 0.44 * watchState,
    watchRotate: 7 - 6 * value,
    auraOpacity: 0.3 + 0.34 * Math.sin(value * Math.PI),
    auraScale: 0.84 + 0.23 * range(value, 0.08, 0.92),
  };
}

function privacyFrame(progress, stepCount = 4) {
  const frame = storyFrame(progress, stepCount);
  const value = frame.progress;
  const cloud = range(value, 0.14, 0.3);
  const relay = range(value, 0.38, 0.53);
  const expiry = range(value, 0.63, 0.78);

  return {
    ...frame,
    deviceOpacity: 1 - 0.45 * range(value, 0.72, 0.94),
    deviceX: -22 * range(value, 0.12, 0.32),
    deviceY: -14 * range(value, 0.12, 0.32),
    deviceScale: 1 - 0.08 * range(value, 0.72, 0.94),
    cloudOpacity: 0.18 + 0.82 * cloud,
    cloudX: 24 * (1 - cloud),
    cloudY: 12 * (1 - cloud),
    cloudScale: 0.9 + 0.1 * cloud,
    relayOpacity: 0.12 + 0.88 * relay,
    relayX: 30 * (1 - relay),
    relayY: 18 * (1 - relay),
    relayScale: 0.88 + 0.12 * relay,
    expiryOpacity: 0.12 + 0.88 * expiry,
    expiryX: -28 * (1 - expiry),
    expiryY: 16 * (1 - expiry),
    expiryScale: 0.86 + 0.14 * expiry,
    expiryRotate: -90 + 240 * expiry,
    pathA: cloud,
    pathB: relay,
    shieldScale: 0.86 + 0.14 * range(value, 0.04, 0.22),
    shieldOpacity: 0.42 + 0.58 * range(value, 0.04, 0.22),
  };
}

function finalFrame(progress) {
  const value = clamp(progress);
  const productsSettle = range(value, 0.04, 0.38);
  const assemble = range(value, 0.34, 0.78);
  const resolve = range(value, 0.76, 0.94);
  return {
    progress: value,
    spread: 1 - assemble,
    pieceOpacity: 1 - 0.9 * assemble,
    iconScale: 0.78 + 0.22 * assemble,
    atmosphereScale: 0.92 + 0.12 * assemble,
    productsOpacity: 1 - resolve,
    productsRotate: -18 + 18 * productsSettle,
    productsScale: 1.08 - 0.18 * resolve,
    phoneX: -96 + 96 * productsSettle - 28 * assemble,
    phoneY: -54 + 54 * productsSettle - 24 * assemble,
    phoneRotate: -14 + 14 * productsSettle,
    phoneScale: 0.86 + 0.14 * productsSettle - 0.16 * resolve,
    watchX: 104 - 104 * productsSettle + 34 * assemble,
    watchY: 62 - 62 * productsSettle + 22 * assemble,
    watchRotate: 16 - 16 * productsSettle,
    watchScale: 0.86 + 0.14 * productsSettle - 0.16 * resolve,
  };
}

function downloadHeroFrame(progress) {
  const value = clamp(progress);
  const settle = range(value, 0.02, 0.22);
  const focus = range(value, 0.26, 0.68);
  const handoff = range(value, 0.72, 0.98);
  return {
    progress: value,
    copyOpacity: 1 - 0.92 * handoff,
    copyY: -34 * handoff,
    copyScale: 1 - 0.035 * handoff,
    stageX: 34 * focus - 48 * handoff,
    stageY: -18 * settle - 36 * handoff,
    stageScale: 0.94 + 0.06 * settle + 0.1 * focus - 0.06 * handoff,
    macX: 38 * (1 - settle) - 38 * focus,
    macY: 24 * (1 - settle) - 28 * focus,
    macRotate: 5 * (1 - settle) - 3 * focus,
    macScale: 0.9 + 0.1 * settle + 0.14 * focus,
    phoneX: -34 * settle - 78 * focus,
    phoneY: 58 * (1 - settle) + 18 * focus,
    phoneRotate: -9 + 5 * settle - 3 * focus,
    phoneScale: 0.86 + 0.14 * settle - 0.08 * focus,
    tabletX: 54 * settle + 92 * focus,
    tabletY: 42 * (1 - settle) + 22 * focus,
    tabletRotate: 8 - 5 * settle + 2 * focus,
    tabletScale: 0.82 + 0.18 * settle - 0.1 * focus,
    watchX: 48 * (1 - settle) + 72 * focus,
    watchY: 64 * (1 - settle) + 28 * focus,
    watchRotate: 10 - 6 * settle,
    watchScale: 0.84 + 0.16 * settle - 0.06 * focus,
    orbitRotate: -18 + value * 142,
    orbitScale: 0.82 + 0.2 * settle + 0.16 * focus,
    chipOpacity: settle * (1 - handoff),
    chipY: 18 * (1 - settle) - 20 * handoff,
  };
}

function downloadMacFrame(progress, stepCount = 3) {
  const frame = storyFrame(progress, stepCount);
  const value = frame.progress;
  const align = range(value, 0.04, 0.3);
  const populate = range(value, 0.28, 0.62);
  const menu = range(value, 0.62, 0.86);
  const tail = range(value, 0.94, 1);
  return {
    ...frame,
    deviceX: 30 * (1 - align) - 22 * tail,
    deviceY: 34 * (1 - align) - 18 * tail,
    deviceRotateX: 7 * (1 - align),
    deviceRotateY: -9 + 9 * align,
    deviceScale: 0.88 + 0.12 * align + 0.08 * populate - 0.04 * tail,
    overlayOpacity: populate,
    overlayY: 12 * (1 - populate),
    menuOpacity: menu * (1 - tail),
    menuX: 54 * (1 - menu),
    menuY: -22 * menu,
    menuScale: 0.92 + 0.08 * menu,
    auraOpacity: 0.28 + 0.34 * Math.sin(value * Math.PI),
    auraScale: 0.88 + 0.2 * Math.sin(value * Math.PI),
  };
}

function timeSpineFrame(progress) {
  const value = clamp(progress);
  const settle = range(value, 0.002, 0.032);
  const exit = range(value, 0.94, 0.995);
  return {
    opacity: (0.2 + 0.62 * settle) * (1 - exit),
    x: -42 * (1 - settle),
    y: 18 * (1 - settle),
    rotate: 90 * (1 - settle),
    scale: 0.56 + 0.44 * settle + 0.18 * Math.sin(value * Math.PI),
    marker: value,
  };
}

const reducedMotionMedia = globalThis.matchMedia?.("(prefers-reduced-motion: reduce)");
const desktopCinematicMedia = globalThis.matchMedia?.("(min-width: 901px) and (min-height: 700px)");
const downloadDesktopMedia = globalThis.matchMedia?.("(min-width: 1101px) and (min-height: 700px)");
const tabletStoryMedia = globalThis.matchMedia?.("(min-width: 761px) and (min-height: 640px)");
const supportsScrollMotion = !(reducedMotionMedia?.matches ?? false) && "requestAnimationFrame" in globalThis;
const scrollPosition = () => globalThis.scrollY || document.documentElement?.scrollTop || 0;
const scrollMotionTasks = [];

function setNumber(element, name, value, unit = "") {
  element?.style?.setProperty(name, `${value.toFixed(3)}${unit}`);
}

function addPinnedScene({ root, sticky, count, frame, apply, media }) {
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
      if (media && !media.matches) {
        lastProgress = Number.NaN;
        return;
      }
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
    media: desktopCinematicMedia,
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
      setNumber(hero, "--hero-pill-opacity", frame.pillOpacity);
      setNumber(hero, "--hero-pill-x", frame.pillX, "px");
      setNumber(hero, "--hero-pill-y", frame.pillY, "px");
      setNumber(hero, "--hero-pill-scale", frame.pillScale);
      setNumber(hero, "--hero-atmosphere-opacity", frame.atmosphereOpacity);
    },
  });
  document.documentElement?.classList.add("hero-ready");
}

const commandStory = document.querySelector?.("[data-command-story]");
const commandSteps = commandStory?.querySelectorAll?.("[data-command-step]") || [];
if (commandStory && commandSteps.length && supportsScrollMotion) {
  addPinnedScene({
    root: commandStory,
    sticky: commandStory.querySelector(".command-visual-sticky"),
    count: commandSteps.length,
    frame: commandFrame,
    media: desktopCinematicMedia,
    apply(frame) {
      setNumber(commandStory, "--scene-progress", frame.progress);
      setNumber(commandStory, "--command-stage-opacity", frame.stageOpacity);
      setNumber(commandStory, "--command-stage-x", frame.stageX, "px");
      setNumber(commandStory, "--command-stage-y", frame.stageY, "px");
      setNumber(commandStory, "--command-stage-scale", frame.stageScale);
      for (let index = 0; index < commandSteps.length; index += 1) {
        const state = frame.steps[index];
        setNumber(commandSteps[index], "--step-opacity", state.copyOpacity);
        setNumber(commandSteps[index], "--copy-y", state.copyY, "px");
        setNumber(commandSteps[index], "--copy-scale", state.productScale);
      }
      for (const name of ["phone", "input", "review", "timeline"]) {
        for (const prop of ["X", "Y", "Z", "Scale", "Opacity", "RotateY", "RotateZ"]) {
          const key = name + prop;
          if (frame[key] === undefined) continue;
          const unit = prop === "X" || prop === "Y" || prop === "Z" ? "px" : prop.startsWith("Rotate") ? "deg" : "";
          const cssProp = prop.replace(/[A-Z]/g, (letter) => "-" + letter.toLowerCase()).replace(/^-/, "");
          setNumber(commandStory, "--command-" + name + "-" + cssProp, frame[key], unit);
        }
      }
      setNumber(commandStory, "--command-type-progress", frame.typeProgress);
      setNumber(commandStory, "--command-type-complete", frame.typeComplete);
      setNumber(commandStory, "--command-token-opacity", frame.tokenOpacity);
      setNumber(commandStory, "--command-token-y", frame.tokenY, "px");
      setNumber(commandStory, "--command-token-scale", frame.tokenScale);
      setNumber(commandStory, "--command-result-y", frame.resultY, "px");
      setNumber(commandStory, "--command-result-scale", frame.resultScale);
      setNumber(commandStory, "--command-ambiguity-opacity", frame.ambiguityOpacity);
      setNumber(commandStory, "--command-ambiguity-y", frame.ambiguityY, "px");
      setNumber(commandStory, "--command-apply-opacity", frame.applyOpacity);
      for (const name of ["voice", "flight"]) {
        for (const prop of ["Opacity", "X", "Y", "Scale", "Rotate"]) {
          const key = name + prop;
          if (frame[key] === undefined) continue;
          const unit = prop === "X" || prop === "Y" ? "px" : prop === "Rotate" ? "deg" : "";
          setNumber(commandStory, "--command-" + name + "-" + prop.toLowerCase(), frame[key], unit);
        }
      }
      setNumber(commandStory, "--command-orbit-opacity", frame.orbitOpacity);
      setNumber(commandStory, "--command-orbit-rotate", frame.orbitRotate, "deg");
      setNumber(commandStory, "--command-orbit-scale", frame.orbitScale);
      for (const name of ["red", "blue"]) {
        setNumber(commandStory, "--command-" + name + "-opacity", frame[name + "Opacity"]);
        setNumber(commandStory, "--command-" + name + "-x", frame[name + "X"], "px");
        setNumber(commandStory, "--command-" + name + "-scale", frame[name + "Scale"]);
      }
      setNumber(commandStory, "--command-now-y", frame.nowY, "%");
    },
  });
  document.documentElement?.classList.add("command-ready");
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
    media: tabletStoryMedia,
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
    media: desktopCinematicMedia,
    apply(frame) {
      const root = school.querySelector(".school-shell");
      setNumber(root, "--scene-progress", frame.progress);
      setNumber(root, "--school-stage-x", frame.stageX, "px");
      setNumber(root, "--school-stage-y", frame.stageY, "px");
      setNumber(root, "--school-stage-rotate", frame.stageRotate, "deg");
      setNumber(root, "--school-stage-rotate-y", frame.stageRotateY, "deg");
      setNumber(root, "--school-stage-scale", frame.stageScale);
      setNumber(root, "--school-class-build-opacity", frame.classOpacity);
      setNumber(root, "--school-aura-opacity", frame.auraOpacity);
      setNumber(root, "--school-aura-scale", frame.auraScale);
      for (let index = 0; index < schoolSteps.length; index += 1) {
        const state = frame.steps[index];
        setNumber(schoolSteps[index], "--step-opacity", state.copyOpacity);
        setNumber(schoolSteps[index], "--copy-y", state.copyY, "px");
      }
      for (const name of ["search", "class", "elective", "timetable", "meal"]) {
        const state = frame[name];
        setNumber(root, "--school-" + name + "-opacity", state.opacity);
        setNumber(root, "--school-" + name + "-x", state.productRotate * 8, "px");
        setNumber(root, "--school-" + name + "-y", state.productY, "px");
        setNumber(root, "--school-" + name + "-scale", state.productScale);
      }
    },
  });
  document.documentElement?.classList.add("school-ready");
}

const rhythm = document.querySelector?.("[data-rhythm-story]");
const rhythmSteps = rhythm?.querySelectorAll?.("[data-rhythm-step]") || [];
if (rhythm && rhythmSteps.length && supportsScrollMotion) {
  addPinnedScene({
    root: rhythm,
    sticky: rhythm.querySelector(".rhythm-visual-sticky"),
    count: rhythmSteps.length,
    frame: rhythmFrame,
    media: desktopCinematicMedia,
    apply(frame) {
      setNumber(rhythm, "--scene-progress", frame.progress);
      for (let index = 0; index < rhythmSteps.length; index += 1) {
        const state = frame.steps[index];
        setNumber(rhythmSteps[index], "--step-opacity", state.copyOpacity);
        setNumber(rhythmSteps[index], "--copy-y", state.copyY, "px");
        setNumber(rhythmSteps[index], "--copy-scale", state.productScale);
      }
      setNumber(rhythm, "--rhythm-phone-x", frame.phoneX, "px");
      setNumber(rhythm, "--rhythm-phone-y", frame.phoneY, "px");
      setNumber(rhythm, "--rhythm-phone-scale", frame.phoneScale);
      setNumber(rhythm, "--rhythm-phone-rotate-y", frame.phoneRotateY, "deg");
      setNumber(rhythm, "--rhythm-phone-rotate-z", frame.phoneRotateZ, "deg");
      setNumber(rhythm, "--rhythm-chrome-opacity", frame.chromeOpacity);
      setNumber(rhythm, "--rhythm-chrome-y", frame.chromeY, "px");
      setNumber(rhythm, "--rhythm-chrome-scale", frame.chromeScale);
      setNumber(rhythm, "--rhythm-grid-top", frame.gridTop, "px");
      setNumber(rhythm, "--rhythm-grid-y", frame.gridY, "px");
      setNumber(rhythm, "--rhythm-grid-scale", frame.gridScale);
      setNumber(rhythm, "--rhythm-event-opacity", frame.eventOpacity);
      setNumber(rhythm, "--rhythm-event-x", frame.eventX, "px");
      setNumber(rhythm, "--rhythm-event-y", frame.eventY, "px");
      setNumber(rhythm, "--rhythm-event-scale-y", frame.eventScaleY);
      setNumber(rhythm, "--rhythm-handle-opacity", frame.handleOpacity);
      setNumber(rhythm, "--rhythm-now-y", frame.nowY, "%");
      setNumber(rhythm, "--rhythm-live-opacity", frame.liveOpacity);
      setNumber(rhythm, "--rhythm-live-x", frame.liveX, "px");
      setNumber(rhythm, "--rhythm-live-y", frame.liveY, "px");
      setNumber(rhythm, "--rhythm-live-scale", frame.liveScale);
      setNumber(rhythm, "--rhythm-morning-opacity", frame.morningOpacity);
      setNumber(rhythm, "--rhythm-day-opacity", frame.dayOpacity);
      setNumber(rhythm, "--rhythm-evening-opacity", frame.eveningOpacity);
      setNumber(rhythm, "--rhythm-clock-opacity", frame.clockOpacity);
      setNumber(rhythm, "--rhythm-clock-y", frame.clockY, "px");
    },
  });
  document.documentElement?.classList.add("rhythm-ready");
}

const devices = document.querySelector?.("[data-device-story]");
const deviceSteps = devices?.querySelectorAll?.("[data-device-step]") || [];
if (devices && deviceSteps.length && supportsScrollMotion) {
  addPinnedScene({
    root: devices.querySelector(".device-story-shell"),
    sticky: devices.querySelector(".device-visual-sticky"),
    count: deviceSteps.length,
    frame: deviceFrame,
    media: desktopCinematicMedia,
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
      setNumber(root, "--device-tablet-opacity", frame.tabletOpacity);
      setNumber(root, "--device-tablet-x", frame.tabletX, "px");
      setNumber(root, "--device-tablet-y", frame.tabletY, "px");
      setNumber(root, "--device-tablet-scale", frame.tabletScale);
      setNumber(root, "--device-tablet-rotate", frame.tabletRotate, "deg");
      setNumber(root, "--device-live-opacity", frame.liveOpacity);
      setNumber(root, "--device-live-x", frame.liveX, "px");
      setNumber(root, "--device-live-y", frame.liveY, "px");
      setNumber(root, "--device-live-scale", frame.liveScale);
      setNumber(root, "--device-island-opacity", frame.islandOpacity);
      setNumber(root, "--device-island-x", frame.islandX, "px");
      setNumber(root, "--device-island-y", frame.islandY, "px");
      setNumber(root, "--device-island-scale", frame.islandScale);
      setNumber(root, "--device-mac-event-opacity", frame.macEventOpacity);
      setNumber(root, "--device-mac-event-y", frame.macEventY, "px");
      setNumber(root, "--device-aura-opacity", frame.auraOpacity);
      setNumber(root, "--device-aura-scale", frame.auraScale);
    },
  });
  document.documentElement?.classList.add("device-ready");
}

const privacy = document.querySelector?.("[data-privacy-story]");
const privacySteps = privacy?.querySelectorAll?.("[data-privacy-step]") || [];
if (privacy && privacySteps.length && supportsScrollMotion) {
  addPinnedScene({
    root: privacy,
    sticky: privacy.querySelector(".privacy-visual-sticky"),
    count: privacySteps.length,
    frame: privacyFrame,
    media: desktopCinematicMedia,
    apply(frame) {
      setNumber(privacy, "--scene-progress", frame.progress);
      for (let index = 0; index < privacySteps.length; index += 1) {
        const state = frame.steps[index];
        setNumber(privacySteps[index], "--step-opacity", state.copyOpacity);
        setNumber(privacySteps[index], "--copy-y", state.copyY, "px");
        setNumber(privacySteps[index], "--copy-scale", state.productScale);
      }
      for (const name of ["device", "cloud", "relay", "expiry"]) {
        setNumber(privacy, "--privacy-" + name + "-opacity", frame[name + "Opacity"]);
        setNumber(privacy, "--privacy-" + name + "-x", frame[name + "X"], "px");
        setNumber(privacy, "--privacy-" + name + "-y", frame[name + "Y"], "px");
        setNumber(privacy, "--privacy-" + name + "-scale", frame[name + "Scale"]);
      }
      setNumber(privacy, "--privacy-expiry-rotate", frame.expiryRotate, "deg");
      setNumber(privacy, "--privacy-path-a", frame.pathA);
      setNumber(privacy, "--privacy-path-b", frame.pathB);
      setNumber(privacy, "--privacy-shield-scale", frame.shieldScale);
      setNumber(privacy, "--privacy-shield-opacity", frame.shieldOpacity);
    },
  });
  document.documentElement?.classList.add("privacy-ready");
}

const downloadHero = document.querySelector?.("[data-download-hero]");
const downloadHeroSticky = downloadHero?.querySelector?.(".download-hero-sticky");
if (downloadHero && downloadHeroSticky && supportsScrollMotion) {
  addPinnedScene({
    root: downloadHero,
    sticky: downloadHeroSticky,
    count: 1,
    frame: downloadHeroFrame,
    media: downloadDesktopMedia,
    apply(frame) {
      setNumber(downloadHero, "--download-hero-progress", frame.progress);
      setNumber(downloadHero, "--download-copy-opacity", frame.copyOpacity);
      setNumber(downloadHero, "--download-copy-y", frame.copyY, "px");
      setNumber(downloadHero, "--download-copy-scale", frame.copyScale);
      setNumber(downloadHero, "--download-stage-x", frame.stageX, "px");
      setNumber(downloadHero, "--download-stage-y", frame.stageY, "px");
      setNumber(downloadHero, "--download-stage-scale", frame.stageScale);
      for (const name of ["mac", "phone", "tablet", "watch"]) {
        setNumber(downloadHero, `--download-${name}-x`, frame[name + "X"], "px");
        setNumber(downloadHero, `--download-${name}-y`, frame[name + "Y"], "px");
        setNumber(downloadHero, `--download-${name}-rotate`, frame[name + "Rotate"], "deg");
        setNumber(downloadHero, `--download-${name}-scale`, frame[name + "Scale"]);
      }
      setNumber(downloadHero, "--download-orbit-rotate", frame.orbitRotate, "deg");
      setNumber(downloadHero, "--download-orbit-scale", frame.orbitScale);
      setNumber(downloadHero, "--download-chip-opacity", frame.chipOpacity);
      setNumber(downloadHero, "--download-chip-y", frame.chipY, "px");
    },
  });
  document.documentElement?.classList.add("download-hero-ready");
}

const downloadMacStory = document.querySelector?.("[data-download-mac-story]");
const downloadMacSteps = downloadMacStory?.querySelectorAll?.("[data-download-mac-step]") || [];
if (downloadMacStory && downloadMacSteps.length && supportsScrollMotion) {
  addPinnedScene({
    root: downloadMacStory,
    sticky: downloadMacStory.querySelector(".download-mac-visual"),
    count: downloadMacSteps.length,
    frame: downloadMacFrame,
    media: downloadDesktopMedia,
    apply(frame) {
      setNumber(downloadMacStory, "--download-mac-progress", frame.progress);
      for (let index = 0; index < downloadMacSteps.length; index += 1) {
        const state = frame.steps[index];
        setNumber(downloadMacSteps[index], "--step-opacity", state.copyOpacity);
        setNumber(downloadMacSteps[index], "--copy-y", state.copyY, "px");
      }
      setNumber(downloadMacStory, "--download-mac-device-x", frame.deviceX, "px");
      setNumber(downloadMacStory, "--download-mac-device-y", frame.deviceY, "px");
      setNumber(downloadMacStory, "--download-mac-device-rx", frame.deviceRotateX, "deg");
      setNumber(downloadMacStory, "--download-mac-device-ry", frame.deviceRotateY, "deg");
      setNumber(downloadMacStory, "--download-mac-device-scale", frame.deviceScale);
      setNumber(downloadMacStory, "--download-mac-overlay-opacity", frame.overlayOpacity);
      setNumber(downloadMacStory, "--download-mac-overlay-y", frame.overlayY, "px");
      setNumber(downloadMacStory, "--download-menu-opacity", frame.menuOpacity);
      setNumber(downloadMacStory, "--download-menu-x", frame.menuX, "px");
      setNumber(downloadMacStory, "--download-menu-y", frame.menuY, "px");
      setNumber(downloadMacStory, "--download-menu-scale", frame.menuScale);
      setNumber(downloadMacStory, "--download-mac-aura-opacity", frame.auraOpacity);
      setNumber(downloadMacStory, "--download-mac-aura-scale", frame.auraScale);
    },
  });
  document.documentElement?.classList.add("download-mac-ready");
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
  addPinnedScene({
    root: finalScene,
    sticky: finalScene.querySelector(".final-cta-inner"),
    count: 1,
    frame: finalFrame,
    media: desktopCinematicMedia,
    apply(frame) {
      setNumber(finalScene, "--final-piece-opacity", frame.pieceOpacity);
      setNumber(finalScene, "--final-icon-scale", frame.iconScale);
      setNumber(finalScene, "--final-atmosphere-scale", frame.atmosphereScale);
      setNumber(finalScene, "--final-products-opacity", frame.productsOpacity);
      setNumber(finalScene, "--final-products-rotate", frame.productsRotate, "deg");
      setNumber(finalScene, "--final-products-scale", frame.productsScale);
      setNumber(finalScene, "--final-phone-x", frame.phoneX, "px");
      setNumber(finalScene, "--final-phone-y", frame.phoneY, "px");
      setNumber(finalScene, "--final-phone-r", frame.phoneRotate, "deg");
      setNumber(finalScene, "--final-phone-scale", frame.phoneScale);
      setNumber(finalScene, "--final-watch-x", frame.watchX, "px");
      setNumber(finalScene, "--final-watch-y", frame.watchY, "px");
      setNumber(finalScene, "--final-watch-r", frame.watchRotate, "deg");
      setNumber(finalScene, "--final-watch-scale", frame.watchScale);
      for (let index = 0; index < finalPieces.length; index += 1) {
        const [x, y, rotation] = piecePositions[index];
        setNumber(finalPieces[index], "--piece-x", x * frame.spread, "px");
        setNumber(finalPieces[index], "--piece-y", y * frame.spread, "px");
        setNumber(finalPieces[index], "--piece-r", rotation * frame.spread, "deg");
      }
    },
  });
  document.documentElement?.classList.add("final-ready");
}

const siteHeader = document.querySelector?.("[data-site-header]");
const timeSpine = document.querySelector?.("[data-time-spine]");
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
      const spine = timeSpineFrame(progress);
      setNumber(timeSpine, "--spine-opacity", spine.opacity);
      setNumber(timeSpine, "--spine-x", spine.x, "vw");
      setNumber(timeSpine, "--spine-y", spine.y, "vh");
      setNumber(timeSpine, "--spine-rotate", spine.rotate, "deg");
      setNumber(timeSpine, "--spine-scale", spine.scale);
      setNumber(timeSpine, "--spine-marker", spine.marker);
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
