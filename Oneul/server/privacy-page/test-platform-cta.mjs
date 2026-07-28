import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("./public/app.js", import.meta.url), "utf8");

function render(navigator) {
  const classes = new Set();
  const cta = {
    textContent: "",
    href: "",
    classList: { toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name); } },
    setAttribute() {},
  };
  const note = { textContent: "" };
  const status = { textContent: "" };
  const document = {
    querySelectorAll() { return [cta]; },
    querySelector(selector) {
      if (selector === "[data-platform-note]") return note;
      if (selector === "[data-mac-status]") return status;
      return null;
    },
  };

  vm.runInNewContext(source, { navigator, document });
  return { cta, note, status, classes };
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

console.log("platform CTA checks passed");
