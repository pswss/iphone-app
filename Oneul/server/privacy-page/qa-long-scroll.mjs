#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const playwrightModule = process.env.PLAYWRIGHT_MODULE || "playwright";

let chromium;
try {
  ({ chromium } = require(playwrightModule));
} catch (error) {
  throw new Error(
    `Could not load Playwright from ${playwrightModule}. Set PLAYWRIGHT_MODULE to the package directory.\n${error.message}`,
  );
}

const rawUrl = process.argv[2];
if (!rawUrl || rawUrl === "--help" || rawUrl === "-h") {
  console.log(`Usage:
  PLAYWRIGHT_MODULE=/absolute/path/to/playwright node qa-long-scroll.mjs <base-url>

Optional:
  ONEUL_QA_OUT=/private/tmp/oneul-home-long-qa
  ONEUL_QA_CHANNEL=chrome`);
  process.exit(rawUrl ? 0 : 1);
}

const baseUrl = new URL(rawUrl).href;
const outputDirectory = path.resolve(process.env.ONEUL_QA_OUT || "/private/tmp/oneul-home-long-qa");
const browserChannel = process.env.ONEUL_QA_CHANNEL || "chrome";
const viewports = [
  { name: "desktop-1440", width: 1440, height: 900, desktop: true, longRun: true },
  { name: "desktop-1920", width: 1920, height: 1080, desktop: true },
  { name: "desktop-1280", width: 1280, height: 720, desktop: true },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "tablet-1024", width: 1024, height: 768 },
  { name: "mobile-390", width: 390, height: 844, mobile: true },
  { name: "mobile-393", width: 393, height: 852, mobile: true },
  { name: "mobile-360", width: 360, height: 800, mobile: true },
];

function collectDiagnostics(page, label) {
  const issues = [];
  page.on("console", (message) => {
    if (message.type() === "error") issues.push(`${label} console: ${message.text()}`);
  });
  page.on("pageerror", (error) => issues.push(`${label} page: ${error.message}`));
  page.on("requestfailed", (request) => {
    issues.push(`${label} request: ${request.method()} ${request.url()} — ${request.failure()?.errorText || "failed"}`);
  });
  page.on("response", (response) => {
    if (response.status() >= 400) issues.push(`${label} response: ${response.status()} ${response.url()}`);
  });
  return issues;
}

async function settle(page, delay = 80) {
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  if (delay) await page.waitForTimeout(delay);
}

async function jumpTo(page, target) {
  await page.evaluate((top) => window.scrollTo({ top, left: 0, behavior: "instant" }), target);
  await settle(page);
}

async function forceImageDecode(page) {
  await page.evaluate(async () => {
    const images = Array.from(document.images);
    for (const image of images) image.loading = "eager";
    await Promise.all(images.map((image) => image.decode().catch(() => undefined)));
  });
  await page.waitForFunction(() => Array.from(document.images).every((image) => image.complete), null, {
    timeout: 15_000,
  });
}

async function inspectPage(page) {
  return page.evaluate(() => ({
    scrollHeight: document.documentElement.scrollHeight,
    viewportHeight: innerHeight,
    maxScroll: Math.max(document.documentElement.scrollHeight - innerHeight, 0),
    horizontalOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    sceneNames: Array.from(document.querySelectorAll("[data-major-scene]"), (element) => element.dataset.majorScene),
    brokenImages: Array.from(document.images)
      .filter((image) => !image.complete || image.naturalWidth === 0 || image.naturalHeight === 0)
      .map((image) => image.currentSrc || image.getAttribute("src") || "<missing src>"),
  }));
}

async function assertNoHeavySticky(page, label) {
  const stickyElements = await page.evaluate(() => Array.from(document.body.querySelectorAll("*"))
    .filter((element) => {
      if (element.closest("header, [data-site-header]")) return false;
      return getComputedStyle(element).position === "sticky";
    })
    .map((element) => element.id || element.dataset.majorScene || element.className || element.tagName));
  assert.deepEqual(stickyElements, [], `${label}: mobile has non-header sticky elements`);
}

async function capture(page, name) {
  await settle(page, 150);
  await page.screenshot({ path: path.join(outputDirectory, `${name}.png`), fullPage: false });
}

async function captureCheckpoints(page, viewport, maxScroll) {
  for (const [name, progress] of [["top", 0], ["mid", 0.5], ["final", 1]]) {
    await jumpTo(page, maxScroll * progress);
    await capture(page, `${viewport.name}-${name}`);
  }
}

async function motionSignature(page) {
  return page.evaluate(() => {
    const intersectsViewport = (element) => {
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < innerHeight;
    };
    const activeScenes = Array.from(document.querySelectorAll("[data-major-scene]"))
      .filter(intersectsViewport)
      .map((element) => element.dataset.majorScene);
    const styled = Array.from(document.body.querySelectorAll("[style]"))
      .map((element, index) => ({ element, index }))
      .filter(({ element }) => intersectsViewport(element))
      .map(({ element, index }) => [
        element.id || element.dataset.majorScene || `${element.tagName}:${index}`,
        element.getAttribute("style") || "",
      ]);
    return { activeScenes, styled };
  });
}

async function assertVisibleContent(page, label, requireAll = false) {
  const result = await page.evaluate(() => {
    const candidates = Array.from(document.querySelectorAll("main h1, main h2, main h3, main p"))
      .filter((element) => !element.matches(".visually-hidden"))
      .filter((element) => !element.closest('[aria-hidden="true"], details:not([open])'));
    const isHidden = (element) => {
      const rect = element.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) return true;
      for (let node = element; node && node !== document.body; node = node.parentElement) {
        const style = getComputedStyle(node);
        if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return true;
      }
      return false;
    };
    const hidden = candidates.filter(isHidden);
    const visibleInViewport = candidates.filter((element) => {
      if (isHidden(element)) return false;
      const rect = element.getBoundingClientRect();
      return rect.bottom > 0 && rect.top < innerHeight;
    });
    return {
      count: candidates.length,
      visibleInViewport: visibleInViewport.map((element) => element.textContent.trim().slice(0, 80)),
      hidden: hidden.map((element) => element.textContent.trim().slice(0, 80)),
    };
  });
  assert(result.count > 0, `${label}: no semantic homepage copy found`);
  assert(result.visibleInViewport.length > 0, `${label}: no readable copy in the viewport`);
  if (requireAll) assert.deepEqual(result.hidden, [], `${label}: semantic copy is hidden`);
}

async function runLongScroll(page, initialMaxScroll) {
  await jumpTo(page, 0);
  for (let tick = 0; tick < 300; tick += 1) {
    await page.mouse.wheel(0, 450);
    await page.waitForTimeout(100);
  }
  await settle(page);

  const downPosition = await page.evaluate(() => scrollY);
  const maxScroll = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  assert(maxScroll >= initialMaxScroll, "desktop-1440: page shrank during the long scroll run");
  assert(downPosition < maxScroll - 1, "desktop-1440: 300 fast wheel ticks reached the end of the page");
  await capture(page, "desktop-1440-after-30s");

  const downwardState = await motionSignature(page);
  assert(
    downwardState.activeScenes.length > 0 || downwardState.styled.length > 0,
    "desktop-1440: no motion state found after the long scroll",
  );
  await jumpTo(page, maxScroll);
  await jumpTo(page, downPosition);
  const upwardState = await motionSignature(page);
  assert.deepEqual(upwardState, downwardState, "desktop-1440: motion state differs when reaching the same point in reverse");

  const middle = maxScroll * 0.5;
  await jumpTo(page, middle);
  await page.reload({ waitUntil: "networkidle" });
  await forceImageDecode(page);
  const restoredPosition = await page.evaluate(() => scrollY);
  if (Math.abs(restoredPosition - middle) > 2) await jumpTo(page, middle);
  await assertVisibleContent(page, "desktop-1440 mid-page reload");
  await capture(page, "desktop-1440-mid-reload");
  return {
    elapsedMs: 30_000,
    wheelDistance: 135_000,
    stoppedAt: Math.round(downPosition),
    maxScroll: Math.round(maxScroll),
    remaining: Math.round(maxScroll - downPosition),
  };
}

async function runViewport(browser, viewport) {
  const context = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const issues = collectDiagnostics(page, viewport.name);
  try {
    const response = await page.goto(baseUrl, { waitUntil: "networkidle", timeout: 60_000 });
    assert(response?.ok(), `${viewport.name}: navigation returned ${response?.status() ?? "no response"}`);
    await forceImageDecode(page);
    await settle(page);

    const report = await inspectPage(page);
    assert(report.horizontalOverflow <= 1, `${viewport.name}: ${report.horizontalOverflow}px horizontal overflow`);
    assert.deepEqual(report.brokenImages, [], `${viewport.name}: broken images`);
    assert(report.sceneNames.length >= 30, `${viewport.name}: expected at least 30 major scenes, found ${report.sceneNames.length}`);
    assert.equal(new Set(report.sceneNames).size, report.sceneNames.length, `${viewport.name}: duplicate major scene names`);
    if (viewport.desktop) {
      assert(
        report.scrollHeight >= viewport.height * 150,
        `${viewport.name}: page is only ${(report.scrollHeight / viewport.height).toFixed(1)} viewport-heights long`,
      );
    }
    if (viewport.mobile) await assertNoHeavySticky(page, viewport.name);

    await captureCheckpoints(page, viewport, report.maxScroll);
    const longScroll = viewport.longRun ? await runLongScroll(page, report.maxScroll) : null;
    if (!viewport.longRun) {
      for (const progress of [0.15, 0.35, 0.65, 0.85]) await jumpTo(page, report.maxScroll * progress);
    }
    assert.deepEqual(issues, [], `${viewport.name}: browser diagnostics failed`);
    return {
      name: viewport.name,
      scrollHeight: report.scrollHeight,
      viewportHeights: Number((report.scrollHeight / viewport.height).toFixed(1)),
      scenes: report.sceneNames.length,
      ...(longScroll ? { longScroll } : {}),
    };
  } finally {
    await context.close();
  }
}

async function runResizeCheck(browser) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  const issues = collectDiagnostics(page, "resize");
  try {
    await page.goto(baseUrl, { waitUntil: "networkidle", timeout: 60_000 });
    await forceImageDecode(page);
    const desktop = await inspectPage(page);
    await jumpTo(page, desktop.maxScroll * 0.5);

    await page.setViewportSize({ width: 390, height: 844 });
    await settle(page, 200);
    const mobile = await inspectPage(page);
    assert(mobile.horizontalOverflow <= 1, "resize: horizontal overflow after desktop-to-mobile resize");
    await assertNoHeavySticky(page, "resize mobile");
    await capture(page, "resize-mobile");

    await page.setViewportSize({ width: 1440, height: 900 });
    await settle(page, 200);
    const restored = await inspectPage(page);
    assert(restored.horizontalOverflow <= 1, "resize: horizontal overflow after returning to desktop");
    assert(restored.scrollHeight >= 900 * 150, "resize: long desktop layout was not restored");
    await capture(page, "resize-desktop-restored");
    assert.deepEqual(issues, [], "resize: browser diagnostics failed");
  } finally {
    await context.close();
  }
}

async function runReducedMotionCheck(browser) {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    reducedMotion: "reduce",
  });
  const page = await context.newPage();
  const issues = collectDiagnostics(page, "reduced-motion");
  try {
    await page.goto(baseUrl, { waitUntil: "networkidle", timeout: 60_000 });
    await forceImageDecode(page);
    await settle(page);
    const report = await inspectPage(page);
    assert(report.sceneNames.length >= 30, `reduced-motion: expected at least 30 scenes, found ${report.sceneNames.length}`);
    assert.equal(
      await page.evaluate(() => document.documentElement.classList.contains("motion-ready")),
      false,
      "reduced-motion: motion-ready must not be enabled",
    );
    await assertNoHeavySticky(page, "reduced-motion");
    await assertVisibleContent(page, "reduced-motion", true);
    await captureCheckpoints(page, { name: "reduced-motion" }, report.maxScroll);
    assert.deepEqual(issues, [], "reduced-motion: browser diagnostics failed");
  } finally {
    await context.close();
  }
}

async function runInteractionCheck(browser) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  const issues = collectDiagnostics(page, "interactions");
  try {
    await page.goto(baseUrl, { waitUntil: "networkidle", timeout: 60_000 });
    await page.keyboard.press("Tab");
    assert.equal(await page.evaluate(() => document.activeElement?.classList.contains("skip-link")), true, "keyboard: skip link is not first");

    await page.locator('.locale-switch [data-locale="en"]').click();
    assert.equal(await page.getAttribute("html", "lang"), "en", "locale: English did not apply");
    await page.locator('.locale-switch [data-locale="ko"]').click();
    assert.equal(await page.getAttribute("html", "lang"), "ko-KR", "locale: Korean did not restore");

    await page.locator(".hero-actions .button-secondary").click();
    assert.equal(await page.evaluate(() => location.hash), "#features", "navigation: feature CTA did not update the target");

    await page.setViewportSize({ width: 390, height: 844 });
    await page.locator(".mobile-menu summary").click();
    assert.equal(await page.locator(".mobile-menu").getAttribute("open"), "", "mobile menu did not open");
    await page.locator('.mobile-menu a[href="#school"]').click();
    assert.equal(await page.locator(".mobile-menu").getAttribute("open"), null, "mobile menu did not close after navigation");

    for (const route of ["privacy", "support"]) {
      const response = await context.request.get(new URL(route, baseUrl).href);
      assert(response.ok(), `route: /${route} returned ${response.status()}`);
    }
    const missing = await context.request.get(new URL("definitely-missing", baseUrl).href);
    assert.equal(missing.status(), 404, "route: missing page did not return 404");
    assert.deepEqual(issues, [], "interactions: browser diagnostics failed");
  } finally {
    await context.close();
  }
}

async function runNoScriptCheck(browser) {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    javaScriptEnabled: false,
  });
  const page = await context.newPage();
  const issues = collectDiagnostics(page, "no-script");
  try {
    const response = await page.goto(baseUrl, { waitUntil: "networkidle", timeout: 60_000 });
    assert(response?.ok(), `no-script: navigation returned ${response?.status() ?? "no response"}`);
    const report = await inspectPage(page);
    assert(report.horizontalOverflow <= 1, "no-script: horizontal overflow");
    assert.deepEqual(report.brokenImages, [], "no-script: broken images");
    await assertNoHeavySticky(page, "no-script");
    await assertVisibleContent(page, "no-script", true);
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(outputDirectory, "no-script-top.png"), fullPage: false });
    assert.deepEqual(issues, [], "no-script: browser diagnostics failed");
  } finally {
    await context.close();
  }
}

await fs.mkdir(outputDirectory, { recursive: true });
const launchOptions = { headless: true };
if (browserChannel !== "chromium") launchOptions.channel = browserChannel;
const browser = await chromium.launch(launchOptions);

try {
  const reports = [];
  for (const viewport of viewports) reports.push(await runViewport(browser, viewport));
  await runResizeCheck(browser);
  await runReducedMotionCheck(browser);
  await runInteractionCheck(browser);
  await runNoScriptCheck(browser);
  console.log(JSON.stringify({ baseUrl, browserChannel, outputDirectory, reports }, null, 2));
  console.log("Oneul long-scroll browser QA passed");
} finally {
  await browser.close();
}
