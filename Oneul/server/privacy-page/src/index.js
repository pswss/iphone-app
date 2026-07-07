// 오늘(Oneul) 개인정보 처리방침 — 정적 한 페이지 (한/영)
const HTML = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>오늘(Oneul) 개인정보 처리방침 · Privacy Policy</title>
<style>
  body { font-family: -apple-system, "Apple SD Gothic Neo", sans-serif; max-width: 680px;
         margin: 0 auto; padding: 32px 20px 60px; line-height: 1.75; color: #1c1c2e; }
  h1 { font-size: 1.5em; } h2 { font-size: 1.1em; margin-top: 1.8em; }
  .en { color: #555; }
  hr { border: none; border-top: 1px solid #ddd; margin: 2.5em 0; }
  li { margin: 4px 0; }
  @media (prefers-color-scheme: dark) { body { background: #111; color: #eee; } .en { color: #aaa; } }
</style>
</head>
<body>
<h1>오늘(Oneul) 개인정보 처리방침</h1>
<p><strong>오늘은 계정 없이 동작하며, 개발자는 사용자의 신원을 알 수 없습니다.</strong> 데이터가 어디에 저장되고 언제 기기를 떠나는지 그대로 적습니다.</p>

<h2>일정 데이터</h2>
<ul>
  <li>일정은 <strong>기기</strong>와 사용자의 <strong>개인 iCloud(CloudKit 비공개 데이터베이스)</strong>에만 저장됩니다. 개발자는 접근할 수 없습니다.</li>
</ul>

<h2>잠금화면 실시간 활동(라이브 액티비티) 푸시</h2>
<ul>
  <li>잠금화면 표시를 앱 없이 갱신하기 위해, <strong>푸시 토큰과 그날의 일정 표시 내용(제목·시각)</strong>이 개발자의 서버(Cloudflare)에 전송되어 <strong>최대 3일 후 자동 삭제</strong>됩니다.</li>
  <li>이 데이터는 푸시 전송에만 쓰이며 다른 목적의 분석·공유가 없습니다. 이름·연락처 등 신원 정보와 연결되지 않습니다.</li>
</ul>

<h2>학교 시간표·급식(선택 기능)</h2>
<ul>
  <li>학교를 설정하면 <strong>학교명·학년·반</strong>으로 NEIS(나이스) 공개 데이터를 조회합니다. 계정·개인 식별 정보는 전송되지 않습니다.</li>
</ul>

<h2>음성 입력(선택 기능)</h2>
<ul>
  <li>음성으로 일정을 입력할 때만 마이크를 사용하며, 변환에는 <strong>Apple 음성 인식</strong>이 사용됩니다(Apple의 개인정보 정책 적용).</li>
  <li>자연어 해석은 기기 내(Apple Intelligence 온디바이스)에서 처리됩니다.</li>
</ul>

<h2>캘린더 가져오기·위치(선택 기능)</h2>
<ul>
  <li>사용자가 실행할 때만 Apple/Google 캘린더를 읽어 오며, 가져온 일정은 위의 일정 데이터와 동일하게 저장됩니다.</li>
  <li>위치는 일정 장소를 현재 위치로 지정할 때만 사용되며 저장·전송되지 않습니다.</li>
</ul>

<h2>수집하지 않는 것</h2>
<ul>
  <li>광고·트래킹 SDK 없음, 이용 분석 없음, 계정 없음, 데이터 판매 없음.</li>
</ul>

<p>문의: <a href="mailto:edsok5588@gmail.com">edsok5588@gmail.com</a> · 시행일: 2026-07-07</p>
<hr>
<h1 class="en">Oneul Privacy Policy (English)</h1>
<p class="en"><strong>Oneul works without an account; the developer cannot identify you.</strong></p>
<ul class="en">
  <li><b>Schedules</b> are stored on your device and in your personal iCloud (CloudKit private database). The developer has no access.</li>
  <li><b>Live Activity push:</b> to update the Lock Screen without the app, your push token and the day's displayed schedule content (titles, times) are sent to the developer's server (Cloudflare) and auto-deleted within 3 days. Used solely for push delivery; never linked to your identity.</li>
  <li><b>School timetable/meals (optional):</b> your school name, grade and class are used to query Korea's public NEIS data. No personal identifiers are sent.</li>
  <li><b>Voice input (optional):</b> the microphone is used only while dictating; transcription uses Apple Speech Recognition. Natural-language parsing runs on-device (Apple Intelligence).</li>
  <li><b>Calendar import / location (optional):</b> read only when you trigger it; location is used only to tag an event's place and is never stored or transmitted.</li>
  <li>No ads, no tracking, no analytics, no accounts, no data sale.</li>
</ul>
<p class="en">Contact: <a href="mailto:edsok5588@gmail.com">edsok5588@gmail.com</a> · Effective 2026-07-07</p>
</body>
</html>`;

// 지원 페이지 — App Store '지원 URL'용 (문의처 + 자주 묻는 질문)
const SUPPORT = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>오늘(Oneul) 지원 · Support</title>
<style>
  body { font-family: -apple-system, "Apple SD Gothic Neo", sans-serif; max-width: 680px;
         margin: 0 auto; padding: 32px 20px 60px; line-height: 1.75; color: #1c1c2e; }
  h1 { font-size: 1.5em; } h2 { font-size: 1.1em; margin-top: 1.8em; }
  .card { background: #f4f5fb; border-radius: 14px; padding: 14px 18px; margin: 10px 0; }
  .en { color: #555; }
  @media (prefers-color-scheme: dark) { body { background: #111; color: #eee; }
    .card { background: #1d1e26; } .en { color: #aaa; } }
</style>
</head>
<body>
<h1>오늘(Oneul) 지원</h1>
<p>오늘은 자연어로 입력하는 하루 일정 타임라인 앱입니다. 문제가 있거나 제안이 있으면 언제든 메일 주세요.</p>
<p><strong>문의:</strong> <a href="mailto:edsok5588@gmail.com">edsok5588@gmail.com</a> — 보통 1~2일 안에 답장드려요.</p>

<h2>자주 묻는 질문</h2>
<div class="card"><strong>잠금화면에 일정(실시간 활동)이 안 떠요.</strong><br>
오늘 날짜에 일정이 있어야 표시됩니다. 설정 &gt; 알림에서 '실시간 활동'이 켜져 있는지도 확인해 주세요.</div>
<div class="card"><strong>학교 시간표·급식이 안 나와요.</strong><br>
설정에서 학교·학년·반을 설정하면 자동으로 불러옵니다. 학기 중이 아닐 때(방학)는 시간표가 비어 있을 수 있어요.</div>
<div class="card"><strong>다른 기기와 동기화가 안 돼요.</strong><br>
두 기기 모두 같은 Apple 계정으로 iCloud에 로그인돼 있고, iCloud Drive가 켜져 있어야 합니다.</div>
<div class="card"><strong>데이터를 전부 지우고 싶어요.</strong><br>
설정 &gt; 데이터 초기화에서 지울 수 있습니다. 일정은 기기와 내 iCloud에만 저장되며 개발자는 접근할 수 없어요.</div>

<p><a href="/">개인정보 처리방침 보기</a></p>
<hr>
<p class="en">Oneul is a natural-language daily timeline app. For help or feedback, email
<a href="mailto:edsok5588@gmail.com">edsok5588@gmail.com</a> — we usually reply within 1–2 days.
<a href="/">Privacy Policy</a></p>
</body>
</html>`;

export default {
  async fetch(request) {
    const path = new URL(request.url).pathname;
    const body = path === "/support" ? SUPPORT : HTML;
    return new Response(body, {
      headers: { "content-type": "text/html; charset=utf-8" },
    });
  },
};
