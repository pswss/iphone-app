import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const contentSource = fs.readFileSync(new URL("./public/content/oneul-home.js", import.meta.url), "utf8");
const source = fs.readFileSync(new URL("./public/app.js", import.meta.url), "utf8");
const html = fs.readFileSync(new URL("./public/index.html", import.meta.url), "utf8");
const downloadHtml = fs.readFileSync(new URL("./public/download.html", import.meta.url), "utf8");
const styles = fs.readFileSync(new URL("./public/styles.css", import.meta.url), "utf8");

function render(navigator, prefersReducedMotion = false, page = "home", search = "") {
  const classes = new Set();
  const rootClasses = new Set();
  const attributes = new Map();
  const cta = {
    textContent: "",
    href: "",
    classList: { toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); } },
    setAttribute(name, value) { attributes.set(name, value); },
    removeAttribute(name) { attributes.delete(name); },
  };
  const note = { textContent: "" };
  const status = { textContent: "" };
  const document = {
    body: { dataset: { page } },
    documentElement: { classList: { add(name) { rootClasses.add(name); } } },
    querySelectorAll(selector) {
      if (selector === "[data-platform-cta]") return [cta];
      return [];
    },
    querySelector(selector) {
      if (selector === "[data-platform-note]") return note;
      if (selector === "[data-mac-status]") return status;
      return null;
    },
  };
  const href = `https://example.test/${page === "download" ? "download" : ""}${search}`;
  const sandbox = {
    navigator,
    document,
    URL,
    URLSearchParams,
    location: { href, search },
    history: { replaceState() {} },
    matchMedia() { return { matches: prefersReducedMotion }; },
  };
  vm.runInNewContext(contentSource, sandbox);
  vm.runInNewContext(source, sandbox);
  return {
    cta,
    attributes,
    note,
    status,
    classes,
    rootClasses,
    content: sandbox.ONEUL_HOME_CONTENT,
    heroFrame: sandbox.heroFrame,
    storyFrame: sandbox.storyFrame,
    commandFrame: sandbox.commandFrame,
    schoolFrame: sandbox.schoolFrame,
    rhythmFrame: sandbox.rhythmFrame,
    deviceFrame: sandbox.deviceFrame,
    privacyFrame: sandbox.privacyFrame,
    finalFrame: sandbox.finalFrame,
    flowFrame: sandbox.flowFrame,
    timeSpineFrame: sandbox.timeSpineFrame,
    downloadHeroFrame: sandbox.downloadHeroFrame,
    downloadMacFrame: sandbox.downloadMacFrame,
    applyLocale: sandbox.applyLocale,
  };
}

const mac = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 0 });
assert.equal(mac.cta.textContent, "Mac 출시 상태 보기");
assert.equal(mac.cta.href, "/download?device=mac");
assert(!mac.classes.has("is-unavailable"));

const ipad = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 5 });
assert.equal(ipad.cta.textContent, "iPad용 다운로드");
assert.equal(ipad.cta.href, "/download?device=ipad");
assert(!ipad.classes.has("is-unavailable"));

const windows = render({ userAgent: "Windows NT 10.0", platform: "Win32", maxTouchPoints: 0 });
assert.equal(windows.cta.textContent, "다운로드");
assert.equal(windows.cta.href, "/download");

const downloadIphone = render(
  { userAgent: "iPhone", platform: "iPhone", maxTouchPoints: 5 },
  false,
  "download",
);
assert.equal(downloadIphone.cta.textContent, "App Store에서 받기");
assert.equal(downloadIphone.cta.href, "https://apps.apple.com/kr/app/oneul-calendar/id6788308943");
downloadIphone.applyLocale("en");
assert.equal(downloadIphone.cta.href, "https://apps.apple.com/us/app/oneul-calendar/id6788308943");

const downloadMac = render(
  { userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 0 },
  false,
  "download",
);
assert.equal(downloadMac.cta.textContent, "Mac 출시 상태 보기");
assert.equal(downloadMac.cta.href, "#mac-story");
assert.equal(downloadMac.status.textContent, "네이티브 Mac 앱 · 공개 설치 파일 준비 중");
assert(!downloadMac.attributes.has("download"));

const requestedWatch = render(
  { userAgent: "Windows NT 10.0", platform: "Win32", maxTouchPoints: 0 },
  false,
  "download",
  "?device=watch",
);
assert.equal(requestedWatch.cta.textContent, "App Store에서 받기");
assert.equal(requestedWatch.cta.href, "https://apps.apple.com/kr/app/oneul-calendar/id6788308943");

const reduced = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 0 }, true);
assert(!reduced.rootClasses.has("flow-ready"));
assert(!reduced.rootClasses.has("story-ready"));

const storyStart = mac.storyFrame(0, 4);
assert.equal(storyStart.steps[0].opacity, 1);
assert.equal(storyStart.steps[1].opacity, 0);

const storyMiddle = mac.storyFrame(0.5, 4);
assert.equal(storyMiddle.current, 2);
assert.equal(storyMiddle.steps[1].opacity, 0);
assert.equal(storyMiddle.steps[2].opacity, 1);
assert.equal(storyMiddle.steps[2].copyOpacity, 1);

const storyTransition = mac.storyFrame(0.225, 4);
assert(storyTransition.steps[0].opacity > 0);
assert(storyTransition.steps[1].opacity > 0);
assert(Math.abs(storyTransition.steps[0].opacity + storyTransition.steps[1].opacity - 1) < 0.0001);

const storyEnd = mac.storyFrame(1, 4);
assert.equal(storyEnd.steps[3].opacity, 1);
assert.equal(storyEnd.steps[3].copyOpacity, 0);
assert.equal(storyEnd.steps[3].productScale, 1);
assert.equal(storyEnd.stageOpacity, 0);

const storyClamped = mac.storyFrame(2, 4);
assert.equal(storyClamped.progress, 1);
assert.equal(storyClamped.steps[3].opacity, 1);

const heroStart = mac.heroFrame(0);
const heroEnd = mac.heroFrame(1);
assert.equal(heroStart.copyOpacity, 1);
assert.equal(heroEnd.copyOpacity, 0);
assert.equal(heroStart.watchOpacity, 1);
assert.equal(heroEnd.watchOpacity, 0);

const downloadHeroStart = mac.downloadHeroFrame(0);
const downloadHeroEnd = mac.downloadHeroFrame(1);
assert.equal(downloadHeroStart.copyOpacity, 1);
assert(downloadHeroEnd.copyOpacity < 0.1);
assert(downloadHeroEnd.orbitRotate > downloadHeroStart.orbitRotate);

const downloadMacStart = mac.downloadMacFrame(0, 3);
const downloadMacEnd = mac.downloadMacFrame(1, 3);
assert.equal(downloadMacStart.steps[0].copyOpacity, 1);
assert.equal(downloadMacEnd.steps[2].opacity, 1);
assert.equal(downloadMacEnd.menuOpacity, 0);

const commandStart = mac.commandFrame(0);
const commandEnd = mac.commandFrame(1);
assert.equal(commandStart.inputOpacity, 1);
assert.equal(commandEnd.timelineOpacity, 1);

const schoolStart = mac.schoolFrame(0);
const schoolEnd = mac.schoolFrame(1);
assert.equal(schoolStart.search.opacity, 1);
assert.equal(schoolStart.meal.opacity, 0);
assert.equal(schoolEnd.search.opacity, 0);
assert.equal(schoolEnd.meal.opacity, 1);

const rhythmStart = mac.rhythmFrame(0);
const rhythmEnd = mac.rhythmFrame(1);
assert.equal(rhythmStart.chromeOpacity, 1);
assert.equal(rhythmEnd.eveningOpacity, 1);

const deviceStart = mac.deviceFrame(0);
const deviceEnd = mac.deviceFrame(1);
assert.equal(deviceStart.phoneOpacity, 1);
assert.equal(deviceEnd.macOpacity, 1);

const privacyStart = mac.privacyFrame(0);
const privacyEnd = mac.privacyFrame(1);
assert.equal(privacyStart.pathA, 0);
assert.equal(privacyEnd.pathB, 1);

const finalStart = mac.finalFrame(0);
const finalEnd = mac.finalFrame(1);
assert.equal(finalStart.spread, 1);
assert.equal(finalEnd.spread, 0);

const spineStart = mac.timeSpineFrame(0);
const spineMiddle = mac.timeSpineFrame(0.5);
assert.equal(spineStart.opacity, 0.2);
assert(spineMiddle.opacity > spineStart.opacity);

const flowBefore = mac.flowFrame(0);
assert.equal(flowBefore.opacity, 0.38);
assert.equal(flowBefore.y, 32);
assert.equal(flowBefore.scale, 0.975);

const flowFocused = mac.flowFrame(0.5);
assert.equal(flowFocused.opacity, 1);
assert.equal(flowFocused.y, 0);
assert.equal(flowFocused.visualY, 0);
assert.equal(flowFocused.scale, 1);

const flowAfter = mac.flowFrame(1);
assert.equal(flowAfter.opacity, 0.38);
assert.equal(flowAfter.y, -18);
assert.equal(flowAfter.visualY, -22);
assert(Math.abs(flowAfter.scale - 0.988) < 0.0001);

const contentKeys = [...`${html}\n${downloadHtml}`.matchAll(/data-copy(?:-html|-aria)?="([^"]+)"/g)].map(([, key]) => key);
for (const locale of ["ko", "en"]) {
  const copy = mac.content.locales[locale].copy;
  for (const key of contentKeys) assert.equal(typeof copy[key], "string", `${locale} copy missing: ${key}`);
}

const majorScenes = html.match(/data-major-scene=/g)?.length ?? 0;
assert(majorScenes >= 30, `expected at least 30 major scenes, found ${majorScenes}`);
assert(html.includes("data-hero-scene"));
assert(html.includes("data-command-story"));
assert(html.includes("data-scroll-story"));
assert(html.includes("data-school-story"));
assert(html.includes("data-rhythm-story"));
assert(html.includes("data-device-story"));
assert(html.includes("data-privacy-story"));

const downloadScenes = [...downloadHtml.matchAll(/data-download-major-scene="([^"]+)"/g)].map(([, name]) => name);
assert(downloadHtml.includes("data-download-hero"));
assert(downloadHtml.includes("data-download-mac-story"));
assert.equal(downloadHtml.match(/data-download-device=/g)?.length, 4);
assert.equal(new Set(downloadScenes).size, downloadScenes.length);
assert(downloadScenes.length >= 7, `expected at least 7 download scenes, found ${downloadScenes.length}`);
assert(downloadHtml.includes('href="https://apps.apple.com/kr/app/oneul-calendar/id6788308943"'));
assert.equal(downloadHtml.match(/class="download-recommended"[^>]*hidden/g)?.length, 4);
assert(styles.includes(":lang(ko) :where(h1, h2, h3, p, li, dt, dd)"), "Korean keep-all wrapping rule missing");

const publicRoot = new URL("./public/", import.meta.url);
for (const [, asset] of `${html}\n${downloadHtml}`.matchAll(/(?:src|srcset|href)="(\/(?:assets|content)[^"]+|\/(?:app\.js|styles\.css))"/g)) {
  assert(fs.existsSync(new URL(`.${asset}`, publicRoot)), `missing asset: ${asset}`);
}

console.log(`platform CTA, localized content, assets, ${majorScenes} homepage scenes, and ${downloadScenes.length} download scenes passed`);
