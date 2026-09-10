// Oneul Live Activity 푸시 서버 (Cloudflare Worker)
//
// 앱이 오늘 일정의 "경계 시각별 콘텐츠 상태"를 통째로 등록하면(POST /register),
// cron(매분)이 시각이 된 항목을 APNs로 전송한다.
// - push-to-start: 앱이 꺼져 있어도 아침에 Live Activity 자동 시작
// - update: 일정 경계(시작/끝)마다 앱 없이 정확한 시각에 상태 전환
//
// 프라이버시: 서버는 앱이 만들어 준 payload를 시각에 맞춰 중계만 한다.
// 비밀: APNS_AUTH_KEY(.p8 PEM), APNS_KEY_ID, APPLE_TEAM_ID, REG_KEY(등록 인증용 공유키)

const TOPIC_LA = "com.oneul.app.push-type.liveactivity";

export default {
  async fetch(request, env) {
    if (request.method !== "POST" || new URL(request.url).pathname !== "/register") {
      return new Response("not found", { status: 404 });
    }
    if (!env.REG_KEY || request.headers.get("x-oneul-key") !== env.REG_KEY) {
      return new Response("unauthorized", { status: 401 });
    }
    let body;
    try { body = await request.json(); } catch { return new Response("bad json", { status: 400 }); }

    const { deviceID, updateToken, startToken, sandbox, items, staleAt } = body ?? {};
    if (typeof deviceID !== "string" || !/^[\w-]{1,128}$/.test(deviceID) || !Array.isArray(items) || items.length > 64) return new Response("bad request", { status: 400 });

    const now = Math.floor(Date.now() / 1000);
    const record = {
      expiresAt: now + 3 * 86400,
      updateToken: updateToken || null,
      startToken: startToken || null,
      sandbox: !!sandbox,
      staleAt: Math.min(Number(staleAt) || now + 86400, now + 2 * 86400),
      // item: { at(unix초), event: "start"|"update", state: {...content-state...}, attributes?: {...}, sent?: bool }
      items: items.slice(0, 64).map(i => ({
        at: Number(i.at), event: i.event === "start" ? "start" : "update",
        state: i.state, attributes: i.attributes || null, sent: false,
      })).filter(i => i.at > 0 && i.state),
    };
    await env.SCHEDULES.put(`dev:${deviceID}`, JSON.stringify(record), {
      expiration: record.expiresAt,
    });
    return Response.json({ ok: true, count: record.items.length });
  },

  async scheduled(_event, env, ctx) {
    ctx.waitUntil(tick(env));
  },
};

export async function tick(env) {
  const now = Math.floor(Date.now() / 1000);
  let cursor;
  do {
  const list = await env.SCHEDULES.list({ prefix: "dev:", cursor });
  for (const key of list.keys) {
    const raw = await env.SCHEDULES.get(key.name);
    if (!raw) continue;
    let rec;
    try { rec = JSON.parse(raw); } catch { continue; }

    if (rec.staleAt && now > rec.staleAt) {            // 하루 지난 스케줄 정리
      await env.SCHEDULES.delete(key.name);
      continue;
    }

    let changed = false;
    let firedNow = false;
    for (const item of rec.items) {
      if (item.sent || now - item.at > 600) {            // 10분 넘게 지난 건 스킵(재기동 폭주 방지)
        if (!item.sent && now - item.at > 600) { item.sent = true; changed = true; }
        continue;
      }
      if (item.nextAttemptAt > now) continue;
      if (item.at > now + 65) continue;                  // 다음 분 크론 몫
      if (item.at > now) {                               // 60초 내 도래 → 정각까지 대기 후 발사(±1초)
        await new Promise(r => setTimeout(r, Math.max(0, item.at * 1000 - Date.now())));
      }
      const result = await sendLA(env, rec, item, Math.floor(Date.now() / 1000));
      item.attempts = (item.attempts || 0) + 1;
      item.sent = result.ok || !result.retry || item.attempts >= 3;
      item.sentOK = result.ok;
      if (!item.sent) item.nextAttemptAt = Math.floor(Date.now() / 1000) + 60 * 2 ** (item.attempts - 1);
      if (!result.ok) console.warn(JSON.stringify({ event: "apns_failed", status: result.status, attempt: item.attempts, retry: !item.sent }));
      changed = true;
      firedNow = true;
    }
    // ponytail: KV is eventually consistent; move per-device scheduling to Durable Objects if concurrent registrations cause lost updates.
    if (changed) await env.SCHEDULES.put(key.name, JSON.stringify(rec), { expiration: rec.expiresAt || now + 3 * 86400 });
    if (!firedNow) await maybeRefresh(env, rec, now);
  }
  cursor = list.list_complete ? undefined : list.cursor;
  } while (cursor);
}

// 경계 푸시 사이의 분 단위 재렌더 — 상태는 그대로 다시 보내고, 기기가 렌더 시점의
// 남은 시간을 다시 계산하게 한다(잠금화면 거친 표기가 앱 없이 갱신되는 원리).
// 1시간 넘게 남은 구간은 표기가 'n시간'이라 시간 단위가 바뀌는 분에만 보낸다.
async function maybeRefresh(env, rec, now) {
  if (!rec.updateToken) return;
  const past = rec.items.filter(i => i.at <= now && i.sentOK);
  if (!past.length) return;                              // 아직 LA 시작 전
  const next = rec.items.filter(i => i.at > now).map(i => i.at).sort((a, b) => a - b)[0];
  if (!next) return;                                     // 마지막 경계 이후 — 셀 대상 없음
  const delta = next - now;
  if (delta > 3600 && delta % 3600 >= 60) return;
  const cur = past.reduce((a, b) => (a.at > b.at ? a : b));
  await sendLA(env, rec, { event: "update", state: cur.state }, now);
}

async function sendLA(env, rec, item, now) {
  const isStart = item.event === "start" && rec.startToken;
  const token = isStart ? rec.startToken : rec.updateToken;
  if (!token) return { ok: false, retry: true, status: 0 };

  try {

  const aps = {
    timestamp: now,
    event: isStart ? "start" : "update",
    "content-state": item.state,
  };
  if (isStart) {
    aps["attributes-type"] = "ScheduleActivityAttributes";
    aps["attributes"] = item.attributes || {};
  }
  if (rec.staleAt) aps["stale-date"] = rec.staleAt;

  const host = rec.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const jwt = await apnsJWT(env);
  const res = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    signal: AbortSignal.timeout(10_000),
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": TOPIC_LA,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "apns-expiration": String(now + 600),
    },
    body: JSON.stringify({ aps }),
  });
  return { ok: res.ok, retry: res.status === 429 || res.status >= 500, status: res.status };
  } catch {
    return { ok: false, retry: true, status: 0 };
  }
}

// ── APNs JWT (ES256) — 50분 캐시 ──
let jwtCache = { token: null, at: 0 };

async function apnsJWT(env) {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache.token && now - jwtCache.at < 3000) return jwtCache.token;

  const header = b64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: env.APPLE_TEAM_ID, iat: now }));
  const unsigned = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDER(env.APNS_AUTH_KEY),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));

  jwtCache = { token: `${unsigned}.${b64urlBytes(new Uint8Array(sig))}`, at: now };
  return jwtCache.token;
}

function pemToDER(pem) {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}
function b64url(s) { return b64urlBytes(new TextEncoder().encode(s)); }
function b64urlBytes(bytes) {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
