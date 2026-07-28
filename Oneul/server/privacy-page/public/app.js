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
