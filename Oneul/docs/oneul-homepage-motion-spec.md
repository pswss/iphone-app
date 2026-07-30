# Oneul homepage and download motion specification

This reference describes the implemented homepage and `/download` narratives, motion engine, responsive behavior, assets, accessibility fallbacks, performance constraints, and browser quality assurance. It documents the current code rather than a future design proposal.

## Purpose and audience

Use this document when you change the Oneul homepage structure, copy, assets, animation frames, or quality assurance checks. It is written for frontend, motion, design, accessibility, performance, content, and release work.

The implementation lives in these files:

- `server/privacy-page/public/index.html`: homepage structure and Korean no-JavaScript fallback
- `server/privacy-page/public/download.html`: adaptive download structure and Korean no-JavaScript fallback
- `server/privacy-page/public/styles.css`: visual system, responsive layouts, and motion bindings
- `server/privacy-page/public/app.js`: locale, centralized release links, device recommendation, and scroll frame calculations
- `server/privacy-page/public/content/oneul-home.js`: Korean and English copy
- `server/privacy-page/test-platform-cta.mjs`: deterministic content and frame checks
- `server/privacy-page/qa-long-scroll.mjs`: browser, long-scroll, responsive, resize, and reduced-motion checks

## Product story

Oneul turns an everyday sentence into a visible timeline for today. The homepage starts with a real timeline screen, follows one sentence through interpretation and review, explains the time model, shows the verified student flow, tracks a day from morning to evening, expands across supported Apple devices, states the real data boundaries, and returns the product objects to the Oneul icon.

The page contains 36 named major scenes:

| Chapter | Scene count | Story outcome |
|---|---:|---|
| Hero | 1 | Introduces the promise, phone, Watch, and incoming sentence |
| Command film | 8 | Converts a sentence into a reviewed timeline event |
| Timeline | 6 | Explains duration, overlap, current time, larger screens, and Watch focus |
| Flow line | 1 | Converts the timeline color system into a chapter boundary |
| School | 5 | Follows search, class selection, electives, import, and meal context |
| Daily rhythm | 5 | Compresses the interface, manipulates an event, and shifts from morning to evening |
| Devices | 5 | Reframes the same schedule for iPhone, iPad, Live Activity, Watch, and Mac |
| Privacy | 4 | Distinguishes on-device processing, private storage, relay data, and expiry |
| Final reassembly | 1 | Returns the phone, Watch, color fragments, and icon to one final state |
| **Total** | **36** | |

## Download story and release truth

`/download` is the release gateway linked from the homepage navigation, top CTA, final CTA, and Mac release detail link. It contains seven named scenes: a four-device product reveal, explicit device selection, three native Mac chapters, release status, and a final action.

The page recommends a device from the browser platform or a valid `?device=iphone|ipad|watch|mac` query. Detection only highlights a card and adjusts the CTA; it does not automatically redirect or install anything. All four choices remain visible.

- iPhone and iPad use the official App Store listing: Korean `https://apps.apple.com/kr/app/oneul-calendar/id6788308943`, English `https://apps.apple.com/us/app/oneul-calendar/id6788308943`
- Apple Watch is delivered with the iPhone app and uses the same listing
- The real native `OneulMac` target is shown with verified Mac product UI, while `MAC_DOWNLOAD_URL` remains empty until a signed and notarized public installer exists

## Persistent visual motif

The rainbow time spine is one persistent desktop element, not a separate decoration in each chapter. `timeSpineFrame()` maps total page progress to its position, rotation, scale, opacity, and marker position. The spine begins as a horizontal rail, settles into a fixed vertical timeline, tracks page progress, and fades before the final edge of the document.

The same seven schedule colors also appear in timeline blocks, progress meters, Live Activity bars, school context, and the final icon fragments. These repeated uses preserve the relationship between time, product state, and brand without copying another launch page.

## Motion architecture

The page uses a dependency-free JavaScript motion engine. `addPinnedScene()` measures each scene outside the normal scroll render path. One passive scroll listener batches updates into one `requestAnimationFrame`, and frame functions write numeric CSS custom properties.

Six product chapters use shared pinned visual stages on qualifying desktop layouts:

1. Command film
2. Timeline
3. School
4. Daily rhythm
5. Devices
6. Privacy

The hero and final CTA also use their own pinned stages. A qualifying desktop is at least 901 px wide, at least 700 px tall, and does not request reduced motion. The timeline chapter can also pin at 761 px wide and 640 px tall.

The frame calculators have separate responsibilities:

- `heroFrame()`: sentence pill, product reveal, Watch exit, and hero handoff
- `commandFrame()`: typing, parse tokens, review, ambiguity, apply, event flight, and timeline state
- `storyFrame()`: chapter step state, local step progress, cross-stage handoff, and tail settle
- `schoolFrame()`: native school setup states and timetable assembly
- `rhythmFrame()`: chrome collapse, current-time movement, direct manipulation, Live Activity, and day color
- `deviceFrame()`: phone, tablet, Live Activity, Dynamic Island, Watch, and Mac depth
- `privacyFrame()`: device, private cloud, relay, expiry, path, and shield states
- `finalFrame()`: product orbit, color fragments, and icon reassembly
- `downloadHeroFrame()`: four-device settle, focus, orbit, and handoff on `/download`
- `downloadMacFrame()`: native Mac alignment, populated week, menu-bar card, and chapter exit
- `timeSpineFrame()`: persistent page-level timeline state

The implementation does not use smooth scrolling, scroll suppression, Canvas, WebGL, video, or a frame sequence. Browser wheel, trackpad, touch, keyboard, anchor, Home, and End behavior remain native.

## Desktop scroll budget

The long layout is deliberate. The current desktop scene lengths are:

| Pinned region | CSS scroll length |
|---|---:|
| Hero | `500svh` |
| Command film | 8 steps at `450svh` each |
| Timeline | 6 steps at `450svh` each |
| School | 5 steps at `550svh` each |
| Daily rhythm | 5 steps at `550svh` each |
| Devices | 5 steps at `550svh` each |
| Privacy | 4 steps at `300svh` each |
| Final CTA | `700svh` |

Chrome browser QA measured a 155,400 px document at 1440 by 900, equal to 172.7 viewport heights. This is a document-height measurement, not a guaranteed time for every wheel or trackpad. The deterministic 30s test uses 300 wheel inputs of 450 px with a 100 ms interval and verifies that this input profile does not reach the end.

## Motion tokens

- UI press: 80 to 120 ms
- Hover and navigation: 160 to 260 ms
- Initial hero settle: 900 ms
- Primary easing: `cubic-bezier(0.16, 1, 0.3, 1)`
- Scroll interpolation: clamped smoothstep ranges
- Desktop cinematic threshold: 901 px wide and 700 px tall
- Download-page pin threshold: 1101 px wide and 700 px tall
- Tablet timeline threshold: 761 px wide and 640 px tall
- Scroll writes: transforms, opacity, and bounded CSS custom properties
- Heavy stage containment: `contain: layout paint`

## Animation inventory

Each range is local to its pinned chapter unless the trigger names viewport entry.

| # | Scene | Trigger | Scroll range | Animated elements | Narrative purpose | Desktop behavior | Mobile fallback | Reduced-motion fallback | Performance risk and mitigation |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | `brand-reveal` | First paint and hero scroll | Hero 0 to 100% | Copy, sentence pill, phone, Watch, rail, atmosphere, cue | Introduce the promise and transfer attention to the product | `500svh` pinned hero with staged handoff | Normal-flow hero and device group | Static first frame with all copy and actions | Large product layers use transforms and one bounded atmosphere |
| 2 | `command-arrives` | Command film | 0 to 12.5% | Voice pill, phone, input card, typing cursor | Show natural-language entry | Pinned native phone enters and begins typing | Static native phone above readable copy | Final timeline state remains readable | DOM text avoids a video or frame sequence |
| 3 | `command-understood` | Command film | 12.5 to 25% | Typed phrase, parse tokens, orbit | Separate date, time, and title | Tokens enter inside the same phone | Tokens appear in the static composition | Timeline fallback | Small DOM elements use transform and opacity |
| 4 | `command-preview` | Command film | 25 to 37.5% | Input state, result card, review state | Show the result before saving | Input yields to the review card | Review content remains in document order | Timeline fallback | Only adjacent states overlap |
| 5 | `command-edit` | Command film | 37.5 to 50% | Ambiguity card, result card, apply control | Show correction before commitment | Ambiguity choice enters and settles | Static review composition | Timeline fallback | No interactive claim is made for the decorative replica |
| 6 | `command-apply` | Command film | 50 to 62.5% | Result card, flying event, timeline | Connect approval to placement | Event card crosses into the timeline state | Static input and timeline states | Timeline fallback | Flight uses a single transform layer |
| 7 | `command-duration` | Command film | 62.5 to 75% | Timeline blocks and phone camera | Explain that block height represents duration | Phone scales toward the timeline | Inline timeline screenshot | Inline timeline screenshot | Camera scale stays on the compositor |
| 8 | `command-overlap` | Command film | 75 to 87.5% | Overlapping event blocks and phone depth | Show concurrent events in columns | Timeline depth and focus shift | Inline timeline screenshot | Inline timeline screenshot | No per-frame layout measurement |
| 9 | `command-now-next` | Command film | 87.5 to 100% | Current-time line, next event, stage settle | Return attention to now and next | Current line advances before handoff | Static current line | Static current line | Tail range is bounded to the chapter end |
| 10 | `natural-language` | Timeline | 0 to 16.7% | iPhone timeline, copy, stage | Explain schedule duration with the real screen | First real screenshot holds in the shared stage | Inline iPhone screenshot | Inline iPhone screenshot | Responsive WebP limits decoded size |
| 11 | `timeline-reveal` | Timeline | 16.7 to 33.3% | iPhone crop and focus ring | Isolate overlapping events | Reversible focus handoff | Inline iPhone screenshot | Inline iPhone screenshot | At most adjacent screenshot states blend |
| 12 | `current-line` | Timeline | 33.3 to 50% | Current-time sweep and phone | Explain past versus upcoming time | Current line sweeps across the real screen | Static current line | Static current line | Sweep uses transform, not width animation |
| 13 | `wide-day` | Timeline | 50 to 66.7% | iPhone and iPad stages | Expand the same day to a wider screen | Phone geometry yields to iPad | Inline iPad screenshot | Inline iPad screenshot | Lazy image decode and intrinsic dimensions |
| 14 | `week-expansion` | Timeline | 66.7 to 83.3% | iPad and Mac stages | Compare the same time across seven days | Wide product stage takes focus | Static wide-screen composition | Static wide-screen composition | Large images remain bounded by viewport sizes |
| 15 | `next-moment` | Timeline | 83.3 to 100% | Watch stage and chapter exit | Reduce the day to the next useful item | Watch becomes the final chapter object | Inline Watch screenshot | Inline Watch screenshot | Small Watch source limits memory |
| 16 | `flow-line` | Statement entry and exit | Viewport progress | Seven-color ribbon and statement | Mark the transition from mechanics to daily context | Ribbon expands with section progress | Static ribbon and statement | Static ribbon and statement | Seven solid elements avoid a full-width filter |
| 17 | `school-search` | School chapter | 0 to 20% | Native phone, search field, result card | Begin the verified school setup flow | Search state appears in a pinned phone | Static school setup composition | Timetable state remains visible | DOM-native replica avoids another large image |
| 18 | `school-class` | School chapter | 20 to 40% | Selected school, grade, class controls | Show the required school choices | Search yields to selected-school state | Static selected-school card | Timetable state remains visible | One phone stage owns all states |
| 19 | `school-electives` | School chapter | 40 to 60% | Subject rows, check states, import control | Explain elective selection | Elective rows replace the class state | Static elective composition | Timetable state remains visible | State transitions use parent transforms |
| 20 | `school-timetable` | School chapter | 60 to 80% | Six class blocks and success state | Show imported classes becoming schedules | Class blocks assemble inside the phone | Static timetable grid | Static timetable grid | Child opacity is bounded and stage is contained |
| 21 | `school-meal` | School chapter | 80 to 100% | Meal card and school stage exit | Add daily meal context without leaving today | Meal state closes the chapter | Static meal card | Static timetable and meal context | Dense mobile layout uses one column |
| 22 | `rhythm-morning` | Daily rhythm | 0 to 20% | Morning sky, phone, full chrome, clock | Start with the complete morning overview | Pinned phone holds the full hierarchy | Static phone and copy | Static phone and copy | Decorative sky stays inside one stage |
| 23 | `rhythm-collapse` | Daily rhythm | 20 to 40% | Header, calendar, summary, day grid | Give more space to the timeline | Chrome collapses while the grid rises | Static complete screen | Static complete screen | Transforms avoid height recalculation |
| 24 | `rhythm-direct-manipulation` | Daily rhythm | 40 to 60% | Event block, resize handles, grid | Explain moving and resizing an event | Event translates and scales within the grid | Static event with visible context | Static event with visible context | One event layer changes per frame |
| 25 | `rhythm-live-activity` | Daily rhythm | 60 to 80% | Phone, Live Activity card, current line | Continue now and next outside the app | Live Activity separates from the phone | Static Live Activity card | Static phone and text | Card and phone use independent transforms |
| 26 | `rhythm-evening` | Daily rhythm | 80 to 100% | Evening sky, dimmed events, stage settle | Close the day with less visual density | Palette and hierarchy settle toward evening | Static evening composition | Static readable composition | Large brightness changes use gradual ranges |
| 27 | `phone-tablet` | Devices | 0 to 20% | iPhone, device aura, copy | Show the one-hand daily view | iPhone leads the shared device stage | Static device cluster | Static device cluster | Only the focused device reaches full opacity |
| 28 | `ipad-week` | Devices | 20 to 40% | iPad, iPhone, wide timeline | Show the seven-column iPad layout | Tablet advances while phone recedes | Static iPad screenshot | Static iPad screenshot | Responsive image source limits decode cost |
| 29 | `live-activity` | Devices | 40 to 60% | Live Activity card and Dynamic Island | Show supported glance surfaces | Two bounded overlays advance from the phone | Static Live Activity card; Dynamic Island is omitted on small screens | Static text and device context | Overlays are DOM, not video |
| 30 | `watch-widget` | Devices | 60 to 80% | Watch, phone, Mac depth | Focus on now and next before app launch | Watch advances while other devices recede | Static Watch in device cluster | Static Watch | Short source texture and bounded shadow |
| 31 | `mac-week` | Devices | 80 to 100% | Mac screenshot and schedule overlays | End the ecosystem story with a populated week | Mac moves to the front and event overlays settle | Static Mac composition | Static Mac composition | One screenshot base and small DOM overlays replace another large capture |
| 32 | `privacy-on-device` | Privacy | 0 to 25% | Device orbit, shield, copy | State where schedule language is interpreted | Device and shield enter in a pinned diagram | Static diagram and full copy | Static diagram and full copy | Abstract shapes use borders and transforms |
| 33 | `privacy-private-cloud` | Privacy | 25 to 50% | Device, private cloud, first path | Distinguish original schedule storage | Private cloud joins the device | Static diagram and copy | Static diagram and copy | Path reveal uses scale rather than layout |
| 34 | `privacy-relay` | Privacy | 50 to 75% | Relay node, second path, cloud | Limit the relay claim to Live Activity display data | Relay node appears after private storage | Static diagram and copy | Static diagram and copy | No particle system or network canvas |
| 35 | `privacy-expiry` | Privacy | 75 to 100% | Expiry ring, paths, shield, details | Show the verified maximum three-day expiry | Expiry ring completes the quieter chapter | Static expiry diagram and policy link | Static expiry diagram and policy link | Rotation is limited to one small ring |
| 36 | `product-reassembly` | Final CTA | Final 0 to 100% | Phone, Watch, seven color fragments, icon, CTA | Conclude the product story at the brand mark | `700svh` pinned reassembly and settle | Static product, icon, copy, and CTA | Static product, icon, copy, and CTA | Product orbit and fragments use transforms only |

### Download-page animation inventory

| Scene | Trigger and range | Product purpose and assets | Desktop | Mobile | Reduced motion |
|---|---|---|---|---|---|
| `device-match` | Download hero, 0 to 100% | Recommend without hiding choices; `mac-week.jpg`, responsive iPhone, iPad, and Watch captures | `280svh` pinned reveal; four devices settle, separate, and hand off around the seven-color orbit | Normal-flow product cluster with reduced scale and no pin | Static cluster; no scrub, rotation, or spatial handoff |
| `device-selector` | Device section viewport entry and explicit tab choice | Show requirements and current release action for all four platforms | Two-column cards; the recommended card gains focus while user-selected tabs update the query | One-column cards and touch-safe horizontal tabs | All cards and controls remain available; hover lift is removed |
| `mac-native` | Mac story, 0 to 33.3% | Establish the separate native macOS target using `mac-week.jpg` | First `200svh` pinned step aligns the Mac window in depth | Screenshot precedes readable normal-flow copy | Static screenshot and copy |
| `mac-week-download` | Mac story, 33.3 to 66.7% | Explain the seven-day timeline with bounded DOM schedule overlays | Second `200svh` step populates the week while preserving the same window | Static populated-week composition | Static populated-week composition |
| `mac-menu-download` | Mac story, 66.7 to 100% | Show the menu-bar now-and-next surface | Third `200svh` step brings in the menu-bar card and settles the device | Compact menu card over a reduced Mac stage | Static Mac and menu card with all copy visible |
| `release-truth` | Release-status viewport progress | Separate the live App Store release from the pending Mac installer | Short section-level transform and opacity settle; no pin | Normal-flow status list | Static ready and pending states |
| `download-conclusion` | Final section viewport progress | Return to the selected valid action with `oneul-icon.png` | Bounded section reveal and light response; no scroll trap | Stacked icon, copy, and full-width CTA | Static icon, copy, App Store or Mac-status action |

## DOM-native product presentation

The command, school, rhythm, Live Activity, Dynamic Island, and privacy visuals are DOM-native presentation layers. They reproduce verified Oneul structures from the app source, including the AI input, review card, ambiguity choice, timeline, school search, grade and class selection, elective rows, timetable blocks, meal card, day-grid controls, and glance surfaces.

These layers are not a live web version of the app. They are decorative product explanations hidden from assistive technology. Equivalent headings, descriptions, and real screenshots remain in semantic document order.

The homepage and download Mac scenes use the real application screenshot as their base and add bounded schedule blocks and a menu-bar card in the presentation layer. This prevents the base capture from contradicting the populated-week narrative without claiming that the overlays are an interactive Mac app.

## Responsive behavior

- **Large desktop and laptop**: Viewports at least 901 by 700 use all six pinned product chapters, the pinned hero, the pinned final CTA, the persistent time spine, and full device depth
- **1024 by 768 tablet landscape**: The homepage meets its desktop cinematic query and receives the full long layout; `/download` stays in its one-column, non-pinned tablet composition
- **768 by 1024 tablet portrait**: Only the timeline chapter uses the tablet pin; the other chapters use normal flow
- **Mobile**: All heavy non-header sticky stages are removed. Product visuals precede readable chapter copy, large overlays are reduced, and Dynamic Island and tablet layers are omitted where they would crowd the viewport
- **Short viewports**: The desktop cinematic query does not activate below 700 px in height
- **Download desktop**: At least 1101 by 700, the hero pins for `280svh`; the three-step Mac story uses `200svh` per step. Device selection, release truth, and the conclusion stay in normal document flow
- **Download mobile**: The hero, selector, Mac story, status, and conclusion form a single-column normal-flow page; no non-header product stage pins
- **Download reduced motion**: `supportsScrollMotion` is false, all copy and actions remain visible, spatial transforms are reset, and the orbit, hover lift, and scrubbed Mac handoff are removed
- **No JavaScript**: Semantic Korean copy, screenshots, links, and CTAs remain visible in normal flow

The browser QA measurements show this deliberate split. Qualifying cinematic layouts measure about 172 viewport heights. Portrait tablet and mobile layouts measure about 23 to 26 viewport heights.

## Accessibility behavior

- Semantic headings and copy exist independently of decorative pinned stages
- `prefers-reduced-motion: reduce` prevents `motion-ready`, disables scrubbed pins and the persistent spine, and presents all semantic copy in normal flow
- The reduced-motion composition keeps the final timeline and school timetable visible instead of leaving intermediate UI layers stacked
- `prefers-reduced-transparency: reduce` removes translucent chrome and decorative atmospheres
- `prefers-contrast: more` promotes muted text and diagram boundaries
- `prefers-color-scheme: dark` uses an explicit token set
- Locale controls use `aria-pressed`, navigation uses `aria-current`, and focus remains visible
- Mobile and reduced-motion QA assert that no non-header sticky element remains
- Buttons and controls keep a minimum 44 CSS pixel target where they are interactive

## Assets

Approved assets live in `server/privacy-page/public/assets/`:

- `oneul-icon.png`: approved app icon
- `iphone-timeline.jpg`: baseline iPhone screenshot and JPEG fallback
- `iphone-ai.jpg`: retained approved AI screenshot source
- `ipad-timeline.jpg`: baseline iPad screenshot and JPEG fallback
- `watch-timeline.jpg`: baseline Watch screenshot and JPEG fallback
- `mac-week.jpg`: real Mac application screenshot used beneath schedule overlays
- `iphone-timeline-2x.webp`: 1040 by 2260 responsive WebP, generated from the approved App Store source
- `ipad-timeline-2x.webp`: 1440 by 1920 responsive WebP, generated from the approved App Store source
- `watch-timeline-2x.webp`: 410 by 502 responsive WebP, generated from the approved App Store source

The download hero reuses `mac-week.jpg`, `iphone-timeline-2x.webp`, `ipad-timeline-2x.webp`, `watch-timeline-2x.webp`, their JPEG fallbacks, and `oneul-icon.png`. It introduces no stock imagery or temporary download-only asset. Real-screen scenes use `<picture>` with the high-resolution WebP first and the existing JPEG as fallback.

## Performance considerations

- The page adds no runtime dependency or framework bundle
- One passive scroll listener and one animation-frame scheduler coordinate all scroll motion
- Layout measurements run on initialization, resize, orientation change, page show, font readiness, or observed layout resize, not on the normal scroll render path
- Scene tasks check their media query before applying cinematic state
- Pinned visual stages use `contain: layout paint`
- Motion uses transforms and opacity for primary movement
- The download page reuses already decoded product assets and adds only two frame calculators; no additional runtime dependency is loaded
- High-resolution WebP files are smaller delivery derivatives of the approved source captures
- Noncritical images use lazy loading, asynchronous decode, and intrinsic dimensions
- Mobile and reduced-motion modes remove the long pinned layout
- The persistent spine is one small fixed layer and does not accept pointer input
- Decorative atmosphere animation only runs while the hero is active

A local headless Chrome PerformanceObserver smoke run measured FCP and LCP at 152 ms, CLS at 0.016, no long tasks, 12 requests, and 287,255 encoded bytes. A five-second scrolling sample recorded 587 frames, a 9.1 ms p95 interval, and no interval above 34 ms. These local figures verify this build on the test machine; they are not field Core Web Vitals or a substitute for production-device profiling.

The 172-viewport desktop height is intentional product behavior. Do not shorten it without updating `qa-long-scroll.mjs` and reviewing the complete narrative. Do not add wheel suppression or smooth-scroll interception to enforce a fixed duration.

## Content and CTA editing

- Korean and English copy: `server/privacy-page/public/content/oneul-home.js`
- Homepage Korean progressive-enhancement fallback: `server/privacy-page/public/index.html`
- Download Korean progressive-enhancement fallback: `server/privacy-page/public/download.html`
- Homepage and download scene structure: `server/privacy-page/public/index.html` and `server/privacy-page/public/download.html`
- Motion frame functions: `server/privacy-page/public/app.js`
- Visual and responsive tokens: `server/privacy-page/public/styles.css`
- Official App Store URL: `APP_STORE_URL` at the top of `server/privacy-page/public/app.js`
- Mac installer URL: `MAC_DOWNLOAD_URL` at the top of `server/privacy-page/public/app.js`; keep empty until the installer is signed, notarized, and public
- Download route: `DOWNLOAD_PAGE_URL` at the top of `server/privacy-page/public/app.js`
- Screenshots, logo, icon, and responsive WebP files: `server/privacy-page/public/assets/`
- Verified claims and editing constraints: `server/privacy-page/PRODUCT.md`

## Quality assurance

The long-scroll browser suite was executed from `server/privacy-page` against the local Wrangler server with this exact command:

```bash
env PLAYWRIGHT_MODULE=/Users/pysw/gstack/node_modules/playwright ONEUL_QA_CHANNEL=chrome node qa-long-scroll.mjs http://127.0.0.1:8789
```

The passing report was:

| Viewport | Document height | Viewport heights | Major scenes |
|---|---:|---:|---:|
| `desktop-1440` at 1440 by 900 | 155,400 px | 172.7 | 36 |
| `desktop-1920` at 1920 by 1080 | 185,930 px | 172.2 | 36 |
| `desktop-1280` at 1280 by 720 | 124,736 px | 173.2 | 36 |
| `tablet-768` at 768 by 1024 | 23,163 px | 22.6 | 36 |
| `tablet-1024` at 1024 by 768 | 132,490 px | 172.5 | 36 |
| `mobile-390` at 390 by 844 | 20,806 px | 24.7 | 36 |
| `mobile-393` at 393 by 852 | 20,843 px | 24.5 | 36 |
| `mobile-360` at 360 by 800 | 20,517 px | 25.6 | 36 |

The suite also verified:

- 36 unique major scene names at every viewport
- No horizontal overflow, broken image, console error, page error, failed request, or HTTP error response
- Initial, middle, and final screenshots for all eight viewports
- A 30s run of 300 wheel inputs at 450 px with 100 ms intervals; it stopped at 135,000 of 154,500 scroll pixels, leaving 19,500 px
- Matching motion signatures at the same position after forward and reverse travel
- Readable content after a middle-of-page reload
- Desktop to mobile to desktop resize without stale heavy sticky layouts
- A reduced-motion document without `motion-ready`, heavy sticky elements, or hidden semantic copy
- Keyboard-first skip link focus, Korean and English switching, feature navigation, mobile-menu open and close, `/privacy`, `/support`, and 404 routing
- A JavaScript-disabled document with no heavy sticky layout, hidden semantic copy, broken image, or horizontal overflow

The terminal result was `Oneul long-scroll browser QA passed`. Screenshots were written to `/private/tmp/oneul-home-long-qa`.

Additional checks remain available:

```bash
node --check public/content/oneul-home.js
node --check public/app.js
node test-platform-cta.mjs
wrangler deploy --dry-run --outdir /private/tmp/oneul-home-dist
wrangler dev --port 8789 --ip 127.0.0.1
```

`test-platform-cta.mjs` covers the official App Store URL, homepage-to-download routing, Mac pending behavior, explicit device-query overrides, download frame endpoints, seven unique download scenes, four device cards, localized copy keys, and referenced asset existence. Browser release QA should additionally open `/download` on desktop, mobile, and reduced-motion profiles and verify the tab selection, recommendation-only behavior, App Store actions, Mac status anchor, reverse scroll, resize, and no horizontal overflow.

## Known limitations

- `MAC_DOWNLOAD_URL` remains empty until a signed and notarized public Mac build exists
- The official iPhone and iPad listing is live at the localized Korean and US URLs above; Apple Watch is delivered with the iPhone app and also requires a compatible iPhone
- The native `OneulMac` target exists, but no public Mac installer is linked yet
- The production marketing origin is `https://oneul-privacy.pswss.workers.dev/`; canonical, Open Graph URL, and absolute social-image metadata use this origin
- DOM-native presentation layers explain verified product behavior but are not interactive versions of the native apps
- The deterministic 30s result applies to the tested wheel profile, not every physical wheel or trackpad
- The long-scroll browser suite used the Chrome channel. Safari, Firefox, Edge, and physical iOS or Android devices were not part of this recorded run
