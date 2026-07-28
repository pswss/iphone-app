import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("./public/app.js", import.meta.url), "utf8");
const html = fs.readFileSync(new URL("./public/index.html", import.meta.url), "utf8");

function render(navigator, prefersReducedMotion = false) {
  const classes = new Set();
  const revealClasses = new Set();
  const rootClasses = new Set();
  const cta = {
    textContent: "",
    href: "",
    classList: { toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); } },
    setAttribute() {},
  };
  const note = { textContent: "" };
  const status = { textContent: "" };
  const reveal = {
    classList: {
      add(name) { revealClasses.add(name); },
      remove(name) { revealClasses.delete(name); },
    },
  };
  const document = {
    documentElement: { classList: { add(name) { rootClasses.add(name); } } },
    querySelectorAll(selector) {
      if (selector === "[data-platform-cta]") return [cta];
      if (selector === "[data-reveal]") return [reveal];
      return [];
    },
    querySelector(selector) {
      if (selector === "[data-platform-note]") return note;
      if (selector === "[data-mac-status]") return status;
      return null;
    },
  };
  let revealCallback;
  class IntersectionObserver {
    constructor(callback) { revealCallback = callback; }
    observe() {}
  }

  const sandbox = {
    navigator,
    document,
    IntersectionObserver,
    matchMedia() { return { matches: prefersReducedMotion }; },
  };
  vm.runInNewContext(source, sandbox);
  return {
    cta,
    note,
    status,
    classes,
    reveal,
    revealClasses,
    rootClasses,
    revealCallback,
    storyFrame: sandbox.storyFrame,
  };
}

const mac = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 0 });
assert.equal(mac.cta.textContent, "Mac 출시 정보 보기");
assert.equal(mac.cta.href, "#devices");
assert(mac.classes.has("is-unavailable"));

const ipad = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 5 });
assert.equal(ipad.cta.textContent, "지원 기기 보기");
assert(!ipad.classes.has("is-unavailable"));

const windows = render({ userAgent: "Windows NT 10.0", platform: "Win32", maxTouchPoints: 0 });
assert.equal(windows.cta.textContent, "Mac 버전 보기");

assert(mac.rootClasses.has("motion-ready"));
mac.revealCallback([{ target: mac.reveal, isIntersecting: true, intersectionRatio: 0.2 }]);
assert(mac.revealClasses.has("is-visible"));
mac.revealCallback([{ target: mac.reveal, isIntersecting: false, intersectionRatio: 0 }]);
assert(!mac.revealClasses.has("is-visible"));
mac.revealCallback([{ target: mac.reveal, isIntersecting: true, intersectionRatio: 0.2 }]);
assert(mac.revealClasses.has("is-visible"));

const reduced = render({ userAgent: "Macintosh", platform: "MacIntel", maxTouchPoints: 0 }, true);
assert(!reduced.rootClasses.has("motion-ready"));

const storyStart = mac.storyFrame(0, 4);
assert.equal(storyStart.steps[0].opacity, 1);
assert.equal(storyStart.steps[1].opacity, 0);

const storyMiddle = mac.storyFrame(0.5, 4);
assert.equal(storyMiddle.steps[1].opacity, 0.5);
assert.equal(storyMiddle.steps[2].opacity, 0.5);
assert.equal(storyMiddle.steps[1].copyOpacity, 0);
assert.equal(storyMiddle.steps[2].copyOpacity, 0);
assert.equal(storyMiddle.steps[1].productY, -11);
assert.equal(storyMiddle.steps[2].productY, 14);

const storyEnd = mac.storyFrame(1, 4);
assert.equal(storyEnd.steps[3].opacity, 1);
assert.equal(storyEnd.steps[3].productScale, 1);

const storyClamped = mac.storyFrame(2, 4);
assert.equal(storyClamped.progress, 1);
assert.equal(storyClamped.steps[3].opacity, 1);
assert.equal(html.match(/data-inline-product/g)?.length, 4);

console.log("platform CTA, reveal, and scroll story checks passed");
