import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("./public/app.js", import.meta.url), "utf8");

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

  vm.runInNewContext(source, {
    navigator,
    document,
    IntersectionObserver,
    matchMedia() { return { matches: prefersReducedMotion }; },
  });
  return { cta, note, status, classes, reveal, revealClasses, rootClasses, revealCallback };
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

console.log("platform CTA and scroll reveal checks passed");
