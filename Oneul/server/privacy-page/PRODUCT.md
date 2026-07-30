# Oneul website product context

This reference defines the audience, product claims, conversion path, visual evidence, and experience constraints for the Oneul website. Use it to keep homepage copy and motion aligned with the native application.

## Register and platform

- Register: brand
- Platform: web
- Primary locale: Korean
- Secondary locale: English
- Production origin: `https://oneul-privacy.pswss.workers.dev/`

## Audience

Primary visitors use or are considering iPhone, iPad, Apple Watch, or Mac for daily scheduling. They may arrive from an App Store listing, a shared link, or search while deciding whether Oneul fits their devices and privacy expectations.

## Product purpose

The homepage explains Oneul through the product's main journey: enter a schedule in everyday language, review the interpreted result, place it on a time-proportional day, use student context when relevant, check now and next across supported Apple devices, and understand where schedule data is stored.

Success means a visitor can identify the daily-timeline model, distinguish verified product behavior from presentation, and find the correct platform action without guessing.

## Positioning

Oneul turns everyday Korean into a clear, private timeline for today.

Ten-second memory: “Say it. See your day.”

## Conversion and proof

- **Primary CTA**: Download Oneul for Mac when a signed public build exists
- **Current Mac CTA**: Open truthful device and release information while the public build URL is unavailable
- **Secondary CTA**: Explore the product flow and supported devices
- **Product proof**: Approved iPhone, iPad, Mac, and Watch screenshots; native application targets; on-device rule parsing; supported Apple Intelligence processing; private CloudKit storage; a maximum three-day Live Activity relay retention; no ads; no usage analytics

No testimonial, user count, rating, award, ranking, partnership, price, certification, or unsupported integration may be added.

## Homepage narrative

The implementation contains 36 named major scenes across nine narrative groups:

1. Hero promise and product reveal
2. Eight-step sentence-to-schedule command film
3. Six-step timeline explanation
4. Flow-line transition
5. Five-step student setup and school context
6. Five-step morning-to-evening daily rhythm
7. Five-step Apple device adaptation
8. Four-step privacy boundary
9. Final product and icon reassembly

On a qualifying desktop, six product chapters use pinned visual stages. The hero and final CTA add two more pinned regions. Chrome quality assurance measured 155,400 px, or 172.7 viewport heights, at 1440 by 900.

The long document is a product explanation, not empty scroll distance. Each major range must change interface state, camera hierarchy, shared-object position, or product meaning. Browser scrolling remains native.

## Visual identity

The page should feel calm, direct, native, and quietly cinematic. White remains the main canvas, while short dark chapters create contrast. The seven-color Oneul timeline is the recurring visual motif.

A persistent desktop time spine tracks total page progress. The same colors recur in schedule blocks, progress meters, student context, glance surfaces, and the final icon fragments.

## Product fidelity

Use approved Oneul assets before creating new presentation layers:

1. Real app icon and screenshots
2. Responsive derivatives of approved screenshots
3. DOM-native product presentation based on verified app source
4. Abstract brand geometry tied to the real timeline model

The current timeline scenes use high-resolution `-2x.webp` derivatives with JPEG fallbacks. The command, school, rhythm, Live Activity, Dynamic Island, Mac event, and privacy scenes use DOM-native presentation layers that mirror verified structures in the native source.

DOM-native presentation is explanatory and decorative. It must not be described as a live web app, a real interaction recording, or a pixel-identical native capture. Equivalent semantic copy and real screenshots must remain available.

## Experience constraints

- Show a real timeline before the detailed explanation
- Keep Korean and English homepage copy in `public/content/oneul-home.js`
- Preserve Korean HTML as the no-JavaScript fallback
- Keep the 36 scene identifiers unique and covered by browser QA
- Preserve the six pinned product chapters plus the pinned hero and final CTA on qualifying desktop layouts
- Keep the persistent time spine tied to total page progress
- Use normal document flow on mobile and in reduced-motion mode
- Preserve native wheel, trackpad, touch, keyboard, Home, End, and anchor behavior
- Do not add hard scroll hijacking or input suppression
- Keep privacy language specific to the implemented data flow
- Adapt the CTA by platform without redirecting the whole page
- Do not publish a Mac download URL until the build is signed, notarized, and public

## Responsive and accessible behavior

The full cinematic layout activates at 901 px wide and 700 px tall when reduced motion is not requested. Portrait tablet and mobile layouts use a shorter normal-flow composition. Mobile must not retain non-header sticky stages.

Reduced-motion mode must keep every heading, description, screenshot, privacy statement, and action. It disables the motion engine, persistent spine, scrubbed pins, ambient loops, and large spatial transitions.

Target Web Content Accessibility Guidelines (WCAG) 2.2 AA. Keep keyboard focus visible, interactive controls at least 44 by 44 CSS pixels, meaningful alternative text, semantic heading order, strong contrast, and explicit reduced-transparency, increased-contrast, and dark-mode behavior.

## Performance constraints

- Keep one passive scroll listener and one animation-frame scheduler
- Measure layout outside normal scroll rendering
- Animate transforms and opacity for primary movement
- Gate cinematic updates with the matching media queries
- Contain pinned stages where supported
- Preload only the critical hero image
- Lazy-load and asynchronously decode noncritical screenshots
- Keep responsive WebP sources and intrinsic dimensions
- Avoid WebGL, Canvas, video, or frame sequences unless measured product value justifies their cost
- Avoid additional full-screen blur layers

## Editing locations

- Homepage copy and platform strings: `public/content/oneul-home.js`
- Semantic structure and scene data: `public/index.html`
- Visual and responsive behavior: `public/styles.css`
- Motion calculations and CTA URL: `public/app.js`
- Product screenshots, logo, and icon: `public/assets/`
- Browser long-scroll QA: `qa-long-scroll.mjs`
- Full motion reference: `../../docs/oneul-homepage-motion-spec.md`

## Current release limits

- `MAC_DOWNLOAD_URL` is empty
- No App Store or direct-download URL is published
- Chrome browser QA is recorded; Safari, Firefox, Edge, and physical-device validation remain separate release checks
