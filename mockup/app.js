/* =========================================================
   디자인 목업 동작 로직 (v3 — packed 바)
   - 일정들을 빈틈없이 붙여서 바를 가득 채움(쉬는 시간 간격 제거)
   - 진행 중이면 그 칸 안에서 선이 이동, 쉬는 시간엔 다음 칸 경계에 정지
   - 일정 없으면 "일정 없음"
   ========================================================= */

const DAY_START = 8 * 60;
const DAY_END   = 22 * 60;
const SPAN      = DAY_END - DAY_START;

const RAINBOW = ["#FF453A","#FF9F0A","#FFD60A","#30D158","#0A84FF","#5E5CE6","#BF5AF2"];

let EVENTS = [
  { s:  9*60,    e: 10*60+30, title:"아침 운동",     loc:"홈트" },
  { s: 11*60,    e: 12*60,    title:"팀 회의",       loc:"3층 회의실" },
  { s: 12*60+30, e: 13*60+30, title:"점심",          loc:"성수동" },
  { s: 14*60,    e: 15*60+30, title:"프로젝트 작업", loc:"집중 모드" },
  { s: 16*60,    e: 17*60,    title:"1:1 미팅",      loc:"화상" },
  { s: 18*60,    e: 19*60+30, title:"저녁 약속",     loc:"이태원" },
  { s: 20*60,    e: 21*60,    title:"독서",          loc:"라운지" }
];
EVENTS.sort((a,b)=>a.s-b.s).forEach((ev,i)=> ev.c = RAINBOW[i % RAINBOW.length]);

// ---- packed 레이아웃: 길이 비례 + 최소폭, 빈틈없이 붙임 ----
const MIN_W = 0.05;
let LEFTS = [], WIDTHS = [];
(function buildPacked(){
  const durs = EVENTS.map(e => Math.max(1, e.e - e.s));
  const total = durs.reduce((a,b)=>a+b, 0) || 1;
  let w = durs.map(d => Math.max(d/total, MIN_W));
  const sum = w.reduce((a,b)=>a+b, 0);
  w = w.map(x => x/sum);
  let acc = 0;
  WIDTHS = w;
  LEFTS = w.map(x => { const l = acc; acc += x; return l; });
})();

/** packed 좌표(0~1): 진행 중이면 그 칸 안 비율, 쉬는 시간엔 다음 칸 경계에 정지 */
function packedFraction(now){
  if (EVENTS.length === 0) return 0;
  if (now < EVENTS[0].s) return 0;
  for (let i = 0; i < EVENTS.length; i++){
    const e = EVENTS[i];
    if (now < e.s)  return LEFTS[i];                       // 쉬는 시간 → 경계에 정지
    if (now < e.e)  return LEFTS[i] + WIDTHS[i] * ((now - e.s) / (e.e - e.s)); // 진행 중
  }
  return 1; // 마지막 일정 이후
}

// ---- 포맷 ----
function fmtClock(min){ const h=Math.floor(min/60), m=Math.round(min%60);
  return `${h}:${String(m).padStart(2,"0")}`; }
function fmtKor(min){ let h=Math.floor(min/60), m=Math.round(min%60);
  const ap=h<12?"오전":"오후"; let hh=h%12; if(hh===0)hh=12;
  return `${ap} ${hh}:${String(m).padStart(2,"0")}`; }
function fmtCountdown(sec){ sec=Math.max(0,Math.floor(sec));
  const h=Math.floor(sec/3600), m=Math.floor((sec%3600)/60), s=sec%60;
  const p=(n)=>String(n).padStart(2,"0");
  return h>0 ? `${h}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`; }

// ---- 타임라인 빌드 ----
const timelines = [];
document.querySelectorAll("[data-timeline]").forEach(el=>{
  const segs = EVENTS.map((ev,i)=>{
    const seg = document.createElement("div");
    seg.className = "seg-item";
    seg.style.setProperty("--c", ev.c);
    seg.style.left  = (LEFTS[i] * 100) + "%";
    seg.style.width = (WIDTHS[i] * 100) + "%";
    el.appendChild(seg);
    return seg;
  });
  const ph = document.createElement("div");
  ph.className = "playhead";
  el.appendChild(ph);
  timelines.push({ el, segs, ph });
});

// ---- 이벤트 리스트 ----
const listEl = document.querySelector("[data-eventlist]");
const listRows = listEl ? EVENTS.map(ev=>{
  const row = document.createElement("div");
  row.className = "ev";
  row.style.setProperty("--c", ev.c);
  row.innerHTML =
    `<div class="ev-bar"></div>
     <div class="ev-time">${fmtClock(ev.s)}</div>
     <div class="ev-main">
       <div class="ev-title">${ev.title}</div>
       <div class="ev-loc">${fmtKor(ev.s)} – ${fmtKor(ev.e)} · ${ev.loc}</div>
     </div>`;
  listEl.appendChild(row);
  return row;
}) : [];

// ---- 텍스트 타깃 ----
const curLines = [...document.querySelectorAll("[data-cur-line]")];
const els = {
  countdown: document.querySelector("[data-countdown]"),
  nextLine:  document.querySelector("[data-next-line]"),
  nextChip:  document.querySelector("[data-next-chip]"),
  diTime:    document.querySelector("[data-di-time]"),
  diCount:   document.querySelector("[data-di-count]"),
  curTitle:  document.querySelector("[data-cur-title]"),
  curDot:    document.querySelector("[data-cur-dot]"),
  nextSub:   document.querySelector("[data-next-sub]")
};

// ---- 매 프레임 ----
function update(now){
  const current = EVENTS.find(ev => now >= ev.s && now < ev.e) || null;
  const next    = EVENTS.find(ev => ev.s > now) || null;
  const frac    = packedFraction(now);
  const waiting = !current && !!next;   // 쉬는 시간

  timelines.forEach(tl=>{
    tl.segs.forEach((seg,i)=>{
      seg.classList.toggle("current", current === EVENTS[i]);
      seg.classList.toggle("past", now >= EVENTS[i].e);
    });
    tl.ph.style.left = (frac * 100) + "%";
    tl.ph.classList.toggle("parked", waiting);
  });

  listRows.forEach((row,i)=>{
    const on = EVENTS[i] === current;
    row.classList.toggle("now", on);
    let badge = row.querySelector(".ev-live");
    if (on && !badge){ badge=document.createElement("div");
      badge.className="ev-live"; badge.textContent="LIVE"; row.appendChild(badge); }
    else if (!on && badge){ badge.remove(); }
  });

  curLines.forEach(cl=>{
    if (EVENTS.length === 0) cl.innerHTML = `<span></span>일정 없음`;
    else if (current)        cl.innerHTML = `<span>현재 일정 ·</span> ${current.title}`;
    else if (next)           cl.innerHTML = `<span>대기 중 ·</span> 다음 일정까지`;
    else                     cl.innerHTML = `<span></span>오늘 일정 종료`;
  });

  const target = current ? current.e : (next ? next.s : null);
  const remainSec = target !== null ? (target - now) * 60 : 0;

  if (els.countdown)
    els.countdown.textContent = target !== null
      ? (current ? `종료까지 ${fmtCountdown(remainSec)}` : `다음까지 ${fmtCountdown(remainSec)}`)
      : "오늘 끝";
  if (els.nextLine)
    els.nextLine.textContent = next ? `다음 · ${next.title} ${fmtKor(next.s)}` : "오늘 일정 종료";
  if (els.nextChip)
    els.nextChip.textContent = next ? `다음 · ${next.title} ${fmtClock(next.s)}`
                             : (current ? "오늘 마지막 일정" : "일정 종료");
  if (els.diTime) els.diTime.textContent = next ? fmtClock(next.s)
                                : (current ? fmtClock(current.e) : "—");
  if (els.diCount) els.diCount.textContent = target !== null ? fmtCountdown(remainSec) : "—";
  if (els.curTitle) els.curTitle.textContent = current ? current.title
                                 : (next ? "대기 중" : "일정 없음");
  if (els.curDot) els.curDot.style.color = current ? current.c
                                 : (next ? next.c : "var(--accent-text)");
  if (els.nextSub) els.nextSub.textContent = next ? `다음 · ${next.title} ${fmtKor(next.s)}`
                                 : "오늘 일정 종료";
}

// ---- 가상 시계 ----
let msPerDay = 26000;
let t0 = performance.now();
function loop(t){
  const now = DAY_START + (((t - t0) % msPerDay) / msPerDay) * SPAN;
  update(now);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);

// ---- 컨트롤 ----
document.querySelectorAll("#themeSeg button").forEach(b=>{
  b.onclick = ()=>{
    document.body.className = b.dataset.theme;
    document.querySelectorAll("#themeSeg button").forEach(x=>x.classList.remove("active"));
    b.classList.add("active");
  };
});
const speedBtn = document.getElementById("speedBtn");
const speeds = [
  { ms:26000,  label:"⏩ 데모: 빠르게" },
  { ms:70000,  label:"▶ 데모: 보통" },
  { ms:160000, label:"🐢 데모: 느리게" }
];
let si = 0;
speedBtn.onclick = ()=>{
  si = (si + 1) % speeds.length;
  const t = performance.now();
  const curNow = DAY_START + (((t - t0) % msPerDay) / msPerDay) * SPAN;
  msPerDay = speeds[si].ms;
  t0 = t - ((curNow - DAY_START) / SPAN) * msPerDay;
  speedBtn.textContent = speeds[si].label;
};
