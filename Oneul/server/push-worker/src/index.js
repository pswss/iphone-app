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
    if (request.headers.get("x-oneul-key") !== env.REG_KEY) {
      return new Response("unauthorized", { status: 401 });
    }
    let body;
    try { body = await request.json(); } catch { return new Response("bad json", { status: 400 }); }

    const { deviceID, updateToken, startToken, sandbox, items, staleAt } = body;
    if (!deviceID || !Array.isArray(items)) return new Response("bad request", { status: 400 });

    const record = {
      updateToken: updateToken || null,
      startToken: startToken || null,
      sandbox: !!sandbox,
      staleAt: Number(staleAt) || Math.floor(Date.now() / 1000) + 86400,
      // item: { at(unix초), event: "start"|"update", state: {...content-state...}, attributes?: {...}, sent?: bool }
      items: items.slice(0, 64).map(i => ({
        at: Number(i.at), event: i.event === "start" ? "start" : "update",
        state: i.state, attributes: i.attributes || null, sent: false,
      })).filter(i => i.at > 0 && i.state),
    };
    await env.SCHEDULES.put(`dev:${deviceID}`, JSON.stringify(record), {
      expirationTtl: 3 * 86400,
    });
    return Response.json({ ok: true, count: record.items.length });
  },

  async scheduled(_event, env, ctx) {
    ctx.waitUntil(tick(env));
  },
};

async function tick(env) {
  const now = Math.floor(Date.now() / 1000);
  const list = await env.SCHEDULES.list({ prefix: "dev:" });
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
    for (const item of rec.items) {
      if (item.sent || now - item.at > 600) {            // 10분 넘게 지난 건 스킵(재기동 폭주 방지)
        if (!item.sent && now - item.at > 600) { item.sent = true; changed = true; }
        continue;
      }
      if (item.at > now + 65) continue;                  // 다음 분 크론 몫
      if (item.at > now) {                               // 60초 내 도래 → 정각까지 대기 후 발사(±1초)
        await new Promise(r => setTimeout(r, (item.at - now) * 1000));
      }
      const ok = await sendLA(env, rec, item, Math.floor(Date.now() / 1000));
      item.sent = true;                                  // 실패해도 1회만(무한 재시도 방지)
      item.sentOK = ok;
      changed = true;
    }
    if (changed) await env.SCHEDULES.put(key.name, JSON.stringify(rec), { expirationTtl: 3 * 86400 });
  }
}

async function sendLA(env, rec, item, now) {
  const isStart = item.event === "start" && rec.startToken;
  const token = isStart ? rec.startToken : rec.updateToken;
  if (!token) return false;

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
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": TOPIC_LA,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "apns-expiration": String(now + 600),
    },
    body: JSON.stringify({ aps }),
  });
  return res.ok;
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
