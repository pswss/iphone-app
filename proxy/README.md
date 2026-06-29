# 하루 — NEIS 프록시 (Cloudflare Workers)

앱에 NEIS 키를 박지 않고, **서버(워커)가 키를 들고 NEIS를 대신 호출**하는 무료 프록시.
앱은 키 없이 워커로만 요청 → 키 노출 방지 + 호출 한도 한 곳에서 관리.

```
앱  ──(키 없음)──▶  워커(키 보관)  ──(KEY 주입)──▶  NEIS
```

## 배포 (5분, 무료·카드 불필요)

1. **Node 설치** 후 Wrangler:
   ```bash
   npm install -g wrangler
   ```
2. **Cloudflare 로그인** (무료 계정 생성됨):
   ```bash
   cd proxy
   wrangler login
   ```
3. **NEIS 키를 서버 시크릿으로 저장** (코드엔 절대 안 넣음):
   ```bash
   wrangler secret put NEIS_KEY
   # 프롬프트에 본인 NEIS 키 붙여넣기
   ```
4. **배포**:
   ```bash
   wrangler deploy
   ```
   → `https://oneul-neis-proxy.<계정>.workers.dev` 같은 주소가 나옴.

5. **앱에 프록시 주소 연결** — `Oneul/Oneul/Features/School/NEIS.swift`의 `NEISConfig`:
   ```swift
   static let proxyBase = "https://oneul-neis-proxy.<계정>.workers.dev/hub/"
   ```
   비워두면(`""`) 기존처럼 NEIS 직접 호출(키 사용). 채우면 키 없이 프록시 사용.

## 동작 확인
```bash
curl "https://oneul-neis-proxy.<계정>.workers.dev/hub/schoolInfo?SCHUL_NM=서울&pSize=1"
```
JSON이 오면 성공. (앱이 쓰는 엔드포인트만 허용: schoolInfo·classInfo·mealServiceDietInfo·SchoolSchedule·els/mis/his/spsTimetable)

## 운영 메모
- 키는 **워커 시크릿에만** 있음(코드·git 미포함). 키 바꾸려면 `wrangler secret put NEIS_KEY` 다시.
- 워커 주소는 앱 바이너리에서 추출 가능 → 누군가 막 호출할 수 있음. 필요 시:
  - 엔드포인트 화이트리스트(이미 적용) + 동일요청 60초 캐시(적용)로 1차 방어.
  - 더 강하게: Cloudflare 레이트리밋 규칙, 또는 App Attest 토큰 검증 추가(추후).
- Cloudflare 무료: 하루 10만 요청. 학생 앱 규모엔 충분.
