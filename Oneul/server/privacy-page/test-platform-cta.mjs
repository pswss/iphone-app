import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const contentSource = fs.readFileSync(new URL("./public/content/oneul-home.js", import.meta.url), "utf8");
const source = fs.readFileSync(new URL("./public/app.js", import.meta.url), "utf8");
const html = fs.readFileSync(new URL("./public/index.html", import.meta.url), "utf8");

function render(navigator, prefersReducedMotion = false) {
  const classes = new Set();
  const rootClasses = new Set();
  const cta = {
    textContent: "",
    href: "",
    classList: { toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); } },
    setAttribute() {},
  };
  const note = { textContent: "" };
  const status = { textContent: "" };
  const document = {
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
  const sandbox = {
    navigator,
    document,
    matchMedia() { return { matches: prefersReducedMotion }; },
  };
  vm.runInNewContext(contentSource, sandbox);
  vm.runInNewContext(source, sandbox);
  return {
    cta,
    note,
    status,
    classes,
    rootClasses,
    content: sandbox.ONEUL_HOME_CONTENT,
    heroFrame: sandbox.heroFrame,
    storyFrame: sandbox.storyFrame,
    schoolFrame: sandbox.schoolFrame,
    deviceFrame: sandbox.deviceFrame,
    finalFrame: sandbox.finalFrame,
    flowFrame: sandbox.flowFrame,
  };
}

const mac = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 0 });
assert.equal(mac.cta.textContent, "Mac 출시 정보 보기");
assert.equal(mac.cta.href, "#devices");
assert(mac.classes.has("is-unavailable"));

const ipad = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 5 });
assert.equal(ipad.cta.textContent, "Apple 기기 지원 보기");
assert(!ipad.classes.has("is-unavailable"));

const windows = render({ userAgent: "Windows NT 10.0", platform: "Win32", maxTouchPoints: 0 });
assert.equal(windows.cta.textContent, "Mac 버전 보기");

const reduced = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 0 }, true);
assert(!reduced.rootClasses.has("flow-ready"));
assert(!reduced.rootClasses.has("story-ready"));

const storyStart = mac.storyFrame(0, 4);
assert.equal(storyStart.steps[0].opacity, 1);
assert.equal(storyStart.steps[1].opacity, 0);

const storyMiddle = mac.storyFrame(0.5, 4);
assert(Math.abs(storyMiddle.steps[1].opacity - 0.5) < 0.0001);
assert(Math.abs(storyMiddle.steps[2].opacity - 0.5) < 0.0001);
assert.equal(storyMiddle.steps[1].copyOpacity, 0);
assert.equal(storyMiddle.steps[2].copyOpacity, 0);
assert(Math.abs(storyMiddle.steps[1].productY + 11) < 0.0001);
assert(Math.abs(storyMiddle.steps[2].productY - 14) < 0.0001);

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

const schoolStart = mac.schoolFrame(0, 3);
const schoolEnd = mac.schoolFrame(1, 3);
assert.equal(schoolStart.selector.opacity, 1);
assert.equal(schoolStart.meal.opacity, 0);
assert.equal(schoolEnd.selector.opacity, 0);
assert.equal(schoolEnd.meal.opacity, 1);

const deviceStart = mac.deviceFrame(0, 3);
const deviceEnd = mac.deviceFrame(1, 3);
assert.equal(deviceStart.phoneOpacity, 1);
assert.equal(deviceEnd.macOpacity, 1);

const finalStart = mac.finalFrame(0);
const finalEnd = mac.finalFrame(1);
assert.equal(finalStart.spread, 1);
assert.equal(finalEnd.spread, 0);

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

const contentKeys = [...html.matchAll(/data-copy(?:-html)?="([^"]+)"/g)].map(([, key]) => key);
for (const locale of ["ko", "en"]) {
  const copy = mac.content.locales[locale].copy;
  for (const key of contentKeys) assert.equal(typeof copy[key], "string", `${locale} copy missing: ${key}`);
}

const majorScenes = html.match(/data-major-scene=/g)?.length ?? 0;
assert(majorScenes >= 10, `expected at least 10 major scenes, found ${majorScenes}`);
assert(html.includes("data-hero-scene"));
assert(html.includes("data-scroll-story"));
assert(html.includes("data-school-story"));
assert(html.includes("data-device-story"));

const publicRoot = new URL("./public/", import.meta.url);
for (const [, asset] of html.matchAll(/(?:src|href)="(\/(?:assets|content)[^"]+|\/(?:app\.js|styles\.css))"/g)) {
  assert(fs.existsSync(new URL(`.${asset}`, publicRoot)), `missing asset: ${asset}`);
}

console.log("platform CTA, localized content, assets, and 14-scene motion checks passed");
