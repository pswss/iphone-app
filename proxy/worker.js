// 하루(Oneul) — NEIS 프록시 (Cloudflare Worker)
// 앱은 KEY 없이 이 워커로 요청하고, 워커가 서버에 보관된 NEIS 키를 주입해 NEIS에 대신 호출한다.
// → 앱 바이너리에 키가 안 박히고, 모든 사용자 호출이 하나의 키 한도에 묶이는 위험만 서버에서 관리.
//
// 배포: 같은 폴더 README.md 참고. 키는 `wrangler secret put NEIS_KEY` 로 서버에만 저장.

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
    if (request.method !== "GET") {
      return json({ error: "method not allowed" }, 405);
    }
    const url = new URL(request.url);
    const m = url.pathname.match(/^\/hub\/([A-Za-z0-9_]+)$/);
    if (!m || !ALLOWED.has(m[1])) {
      return json({ error: "not found" }, 404);
    }
    if (!env.NEIS_KEY) {
      return json({ error: "server key not configured" }, 500);
    }

    // 들어온 쿼리 그대로 전달 + KEY/Type 주입(KEY는 클라이언트가 못 덮어쓰게 마지막에 set)
    const target = new URL(NEIS_BASE + m[1]);
    for (const [k, v] of url.searchParams) {
      if (k.toUpperCase() === "KEY") continue; // 클라이언트가 보낸 KEY는 무시
      target.searchParams.set(k, v);
    }
    if (!target.searchParams.has("Type")) target.searchParams.set("Type", "json");
    target.searchParams.set("KEY", env.NEIS_KEY);

    const upstream = await fetch(target.toString(), {
      headers: { "accept": "application/json" },
      cf: { cacheTtl: 60, cacheEverything: true }, // 동일 요청 60초 캐시(키 한도 절약)
    });

    return new Response(upstream.body, {
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
