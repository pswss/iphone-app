// 하루(Oneul) — NEIS 프록시 (Cloudflare Worker)
// 앱은 KEY 없이 이 워커로 요청하고, 워커가 서버에 보관된 NEIS 키를 주입해 NEIS에 대신 호출한다.
// → 앱 바이너리에 키가 안 박히고, 모든 사용자 호출이 하나의 키 한도에 묶이는 위험만 서버에서 관리.
//
// 배포: 같은 폴더 README.md 참고. 키는 `wrangler secret put NEIS_KEY` 로 서버에만 저장.
// 진단: 쿼리에 ?debug=1 붙이면 NEIS 상태·키 길이·응답 앞부분을 JSON으로 돌려줌(키 값은 노출 안 함).

const NEIS_BASE = "https://open.neis.go.kr/hub/";

// 앱이 실제로 쓰는 엔드포인트만 허용(아무 NEIS 서비스나 프록시되지 않게).
const ALLOWED = new Set([
  "schoolInfo",
  "classInfo",
  "mealServiceDietInfo",
  "SchoolSchedule",
  "elsTimetable", // 초
  "misTimetable", // 중
  "hisTimetable", // 고
  "spsTimetable", // 특수
]);

export default {
  async fetch(request, env) {
    if (request.method !== "GET") return json({ error: "method not allowed" }, 405);

    const url = new URL(request.url);
    const m = url.pathname.match(/^\/hub\/([A-Za-z0-9_]+)$/);
    if (!m || !ALLOWED.has(m[1])) return json({ error: "not found" }, 404);

    const key = (env.NEIS_KEY || "").trim();   // 붙여넣기 공백/개행 제거
    if (!key) return json({ error: "server key not configured" }, 500);

    // 들어온 쿼리 전달 + KEY/Type 주입(KEY·debug는 NEIS로 안 넘김)
    const target = new URL(NEIS_BASE + m[1]);
    for (const [k, v] of url.searchParams) {
      const lk = k.toLowerCase();
      if (lk === "key" || lk === "debug") continue;
      target.searchParams.set(k, v);
    }
    if (!target.searchParams.has("Type")) target.searchParams.set("Type", "json");
    target.searchParams.set("KEY", key);

    // NEIS(webtob) 서버가 비-브라우저 UA를 거부하는 경우가 있어 일반 UA를 명시.
    const upstream = await fetch(target.toString(), {
      headers: {
        "user-agent": "Mozilla/5.0 (compatible; OneulApp/1.0; +https://github.com/pswss/iphone-app)",
        "accept": "application/json, text/plain, */*",
      },
    });
    const body = await upstream.text();

    // 진단 모드: 원인 파악용(키 값 자체는 노출 안 함)
    if (url.searchParams.get("debug") === "1") {
      return json({ keyLen: key.length, neisStatus: upstream.status, sample: body.slice(0, 300) }, 200);
    }

    return new Response(body, {
      status: upstream.status,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  },
};

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
