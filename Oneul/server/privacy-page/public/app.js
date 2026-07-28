// ponytail: Keep one empty URL until a signed, notarized public build exists; replace it when distribution is ready.
const MAC_DOWNLOAD_URL = "";

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

function storyFrame(progress, stepCount) {
  const count = Math.max(1, stepCount);
  const value = Math.min(Math.max(progress, 0), 1);
  const phase = value * (count - 1);
  const current = Math.min(count - 1, Math.floor(phase));
  const local = phase - current;
  const blend = current === count - 1
    ? 0
    : Math.min(Math.max((local - 0.2) / 0.6, 0), 1);
  const eased = blend * blend * (3 - 2 * blend);
  const copyOutProgress = Math.min(Math.max((local - 0.12) / 0.22, 0), 1);
  const copyInProgress = Math.min(Math.max((local - 0.72) / 0.2, 0), 1);
  const copyOut = 1 - copyOutProgress * copyOutProgress * (3 - 2 * copyOutProgress);
  const copyIn = copyInProgress * copyInProgress * (3 - 2 * copyInProgress);
  const steps = Array.from({ length: count }, () => ({
    opacity: 0,
    copyOpacity: 0,
    copyY: 16,
    productY: 18,
    productScale: 0.985,
  }));

  steps[current] = {
    opacity: 1 - eased,
    copyOpacity: current === count - 1 ? 1 : copyOut,
    copyY: -12 * (1 - copyOut),
    productY: -22 * eased,
    productScale: 1 - 0.025 * eased,
  };

  if (current < count - 1) {
    steps[current + 1] = {
      opacity: eased,
      copyOpacity: copyIn,
      copyY: 14 * (1 - copyIn),
      productY: 28 * (1 - eased),
      productScale: 0.975 + 0.025 * eased,
    };
  }

  return {
    progress: value,
    steps,
  };
}

const platform = visitorPlatform();
const ctas = document.querySelectorAll("[data-platform-cta]");
const platformNote = document.querySelector("[data-platform-note]");
const macStatus = document.querySelector("[data-mac-status]");

let label = "Apple 기기 지원 보기";
let href = "#devices";
let unavailable = false;

if (platform === "mac") {
  if (MAC_DOWNLOAD_URL) {
    label = "Mac용 Oneul 다운로드";
    href = MAC_DOWNLOAD_URL;
    if (platformNote) platformNote.textContent = "macOS 26 이상 · 무료";
    if (macStatus) macStatus.textContent = "지금 다운로드";
  } else {
    label = "Mac 출시 정보 보기";
    unavailable = true;
    if (platformNote) platformNote.textContent = "macOS용 공개 배포 파일 준비 중";
  }
} else if (platform === "iphone" || platform === "ipad") {
  label = "지원 기기 보기";
  if (platformNote) platformNote.textContent = "iPhone · iPad · Mac · Apple Watch";
} else {
  label = "Mac 버전 보기";
  if (platformNote) platformNote.textContent = "Oneul은 Apple 기기용 네이티브 앱입니다";
}

for (const cta of ctas) {
  cta.textContent = label;
  cta.href = href;
  cta.classList.toggle("is-unavailable", unavailable);
  if (MAC_DOWNLOAD_URL && platform === "mac") {
    cta.setAttribute("download", "");
  }
}

const revealTargets = document.querySelectorAll("[data-reveal]");
const reducedMotion = globalThis.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

if (revealTargets.length && !reducedMotion && "IntersectionObserver" in globalThis) {
  document.documentElement?.classList.add("motion-ready");
  const revealObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting && entry.intersectionRatio >= 0.18) {
        entry.target.classList.add("is-visible");
      } else if (!entry.isIntersecting) {
        entry.target.classList.remove("is-visible");
      }
    }
  }, { threshold: [0, 0.18], rootMargin: "0px 0px -8% 0px" });

  for (const target of revealTargets) revealObserver.observe(target);
}

const story = document.querySelector("[data-scroll-story]");
const storySteps = story?.querySelectorAll("[data-story-step]") ?? [];
const storyProducts = story?.querySelectorAll("[data-story-product]") ?? [];

if (
  story
  && storySteps.length
  && storySteps.length === storyProducts.length
  && !reducedMotion
  && "requestAnimationFrame" in globalThis
) {
  const storySticky = story.querySelector(".story-visual-sticky");
  let storyTicking = false;
  let storyNeedsMeasure = false;
  let storyStart = 0;
  let storyDistance = 1;
  let lastStoryProgress = Number.NaN;

  const applyStoryFrame = (frame) => {
    if (frame.progress === lastStoryProgress) return;
    lastStoryProgress = frame.progress;

    story.style.setProperty("--story-progress", frame.progress.toFixed(4));

    for (let index = 0; index < storySteps.length; index += 1) {
      const step = storySteps[index];
      const product = storyProducts[index];
      const state = frame.steps[index];
      step.style.setProperty("--step-opacity", state.copyOpacity.toFixed(4));
      step.style.setProperty("--copy-y", `${state.copyY.toFixed(2)}px`);
      product.style.setProperty("--product-opacity", state.opacity.toFixed(4));
      product.style.setProperty("--product-y", `${state.productY.toFixed(2)}px`);
      product.style.setProperty("--product-scale", state.productScale.toFixed(4));
    }
  };

  const scrollY = () => globalThis.scrollY || document.documentElement?.scrollTop || 0;

  const renderStory = () => {
    applyStoryFrame(storyFrame(
      (scrollY() - storyStart) / storyDistance,
      storySteps.length,
    ));
  };

  const measureStory = () => {
    const currentScrollY = scrollY();
    const headerHeight = Number.parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue("--header-height"),
    ) || 0;
    storyStart = story.getBoundingClientRect().top + currentScrollY - headerHeight;
    storyDistance = Math.max(
      story.offsetHeight - (storySticky?.clientHeight || globalThis.innerHeight || 1),
      1,
    );
    lastStoryProgress = Number.NaN;
    renderStory();
  };

  const scheduleStory = (measure = false) => {
    storyNeedsMeasure ||= measure;
    if (storyTicking) return;
    storyTicking = true;
    requestAnimationFrame(() => {
      if (storyNeedsMeasure) measureStory();
      else renderStory();
      storyNeedsMeasure = false;
      storyTicking = false;
    });
  };

  applyStoryFrame(storyFrame(0, storySteps.length));
  document.documentElement?.classList.add("story-ready");
  measureStory();
  globalThis.addEventListener("scroll", () => scheduleStory(), { passive: true });
  globalThis.addEventListener("resize", () => scheduleStory(true));
}
