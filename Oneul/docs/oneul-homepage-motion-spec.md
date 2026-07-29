# Oneul Homepage Motion Specification

## Narrative

Oneul turns everyday language into a visible, private timeline for today. The homepage moves from one spoken sentence to a structured day, then widens that day across student context and Apple devices before returning every visual fragment to the Oneul app icon.

The recurring motif is the rainbow time line from the real app icon and schedule UI. It begins as a rail behind the hero phone, becomes the story progress meter and current-time marker, expands across the transition statement, organizes school data, and reassembles inside the final icon.

## Scene List

1. Brand reveal
2. Hero object handoff
3. Natural-language input
4. Timeline reveal
5. Wide-day expansion
6. Next-moment focus
7. Flow-line transition
8. School selection
9. School timetable assembly
10. Meal and academic context
11. iPhone and iPad continuity
12. Watch and widget focus
13. Mac week reassembly
14. Privacy boundary and final product reassembly

## Motion Architecture

The page uses the existing dependency-free JavaScript scroll engine. It batches all scroll work into one `requestAnimationFrame`, measures only on load, resize, orientation change, font readiness, `pageshow`, or observed layout resize, and writes compositor-friendly CSS custom properties. There is no smooth-scroll dependency, scroll hijacking, Canvas, WebGL, video, or frame sequence.

Four desktop scenes are pinned: hero handoff, the four-step product story, the student story, and the device story. The same semantic copy and real screenshots remain in normal document flow when JavaScript is unavailable. Mobile removes the heavy pinned compositions and presents the screenshots and feature UI inline. Reduced motion never initializes the scrubbed scene engine.

### Motion Tokens

- UI press: 80–120 ms
- Hover and navigation: 160–260 ms
- Initial hero settle: 900 ms
- Primary easing: `cubic-bezier(0.16, 1, 0.3, 1)`
- Scene interpolation: clamped smoothstep
- Display translation ceiling: 56 px
- Product rotation ceiling: 8 degrees
- Active full-screen blur ceiling: 64 px, limited to one decorative layer
- Desktop pin threshold: 901 px wide and 700 px tall
- Tablet product-story pin threshold: 761 px wide and 640 px tall

## Animation Inventory

| Scene | Trigger | Scroll range | Animated elements | Narrative purpose | Desktop behavior | Mobile fallback | Reduced-motion fallback | Performance risk | Mitigation |
|---|---|---|---|---|---|---|---|---|---|
| Brand reveal | First paint | 0–900 ms | Hero copy, device group, atmosphere | Establish the Oneul promise and product immediately | Controlled settle with a single ambient field | Same short settle, smaller field | Static first frame | Long first-paint animation | Content is visible before animation; no preloader |
| Hero handoff | Hero scroll | 0–100% of hero pin | Copy, phone, watch, rainbow rail, scroll cue | Carry the hero phone into the product explanation | 180 svh pinned scene; watch exits while phone straightens and scales | Normal-flow hero with no pin | Static hero | Large layer transforms | Transform and opacity only; desktop media gate |
| Natural-language input | Product story step 1 | 0–33% | AI-entry screenshot, copy, aura | Show the real input surface | Shared pinned product stage | Inline screenshot beside copy | Inline screenshot | Screenshot decode during scroll | Lazy decoding; hero image is the only preload |
| Timeline reveal | Product story step 2 | 20–52% | AI screen, timeline screen, copy | Connect a sentence to a structured day | Reversible cross-transform between real screens | Stacked normal-flow section | Stacked static content | Two overlapping images | Only two visible layers; transform and opacity |
| Wide-day expansion | Product story step 3 | 48–82% | iPhone/iPad stage, copy | Explain spatial expansion on a wider display | Product geometry grows from phone to tablet | Inline iPad screenshot | Inline iPad screenshot | Large tablet texture | Bounded display size and lazy image decoding |
| Next-moment focus | Product story step 4 | 78–100% | Watch screen, copy, stage exit | Reduce the full day to the next useful moment | Watch becomes the only product object, then stage settles out | Inline Watch screenshot | Inline Watch screenshot | Abrupt end-state flash | Tail interpolation and default-visible markup |
| Flow-line transition | Statement entry and exit | Viewport intersection | Rainbow ribbon, statement copy | Turn the product timeline into the site-wide motif | Ribbon expands while the chapter enters | Static full-width ribbon | Static ribbon | Full-width paint | Ribbon uses seven solid elements, no filter |
| School selection | Student step 1 | 0–50% of first step | School selector panel, copy, app window | Show the first real student action | Pinned app window with selector state | Composite school UI above normal-flow copy | Composite school UI | Artificial UI becoming misleading | Labels mirror verified native flow; marked decorative |
| School timetable assembly | Student step 2 | 25–75% | Selector, timetable blocks, copy | Show imported classes becoming today’s schedule | Shared window transitions to six schedule blocks | All panels visible in a readable composite | Composite static layout | Many child transforms | One parent panel transition; child opacity is bounded |
| Meal and academic context | Student step 3 | 50–100% | Timetable, meal panel, academic strip | Connect classes, meals, and school dates | Meal panel replaces timetable and the stage settles | Composite UI with all information visible | Composite static layout | Dense mobile UI | One-column mobile layout and smaller class grid |
| iPhone and iPad continuity | Device step 1 | 0–50% | iPhone, Mac base, copy | Begin cross-device continuity from the daily timeline | Phone leads while Mac remains in depth | Static device cluster | Static device cluster | Three large images in one scene | Lazy decode and fixed intrinsic dimensions |
| Watch and widget focus | Device step 2 | 25–75% | Watch, phone, Mac, copy | Shift attention to glanceable information | Watch scales forward; other devices recede | Static device cluster plus normal copy | Static device cluster | Layer overlap on short screens | Pinned mode requires 700 px height |
| Mac week reassembly | Device step 3 | 50–100% | Mac, phone, watch, copy | Reassemble the same day as a wide weekly view | Mac settles front and center with subtle perspective | Mac remains the dominant static image | Static Mac image | Large hero-size Mac screenshot | 1200 px source, bounded render width, no DPR canvas |
| Privacy and final reassembly | Privacy and final CTA entry | Viewport intersection | Private boundary bars, seven color pieces, icon, CTA | Quiet the motion, show exact data boundaries, and conclude at the brand mark | Bars contract inside the boundary; color pieces return to the icon | Static boundary and icon composition | Static boundary and icon | Decorative atmosphere blur | One bounded layer; disabled by reduced transparency |

## Responsive Behavior

- Large desktop: all three long-form pinned systems, full device depth, longer scene ranges.
- Laptop: the same architecture with bounded heights and product sizes.
- Tablet: only the four-step product story remains pinned; school and device stories use normal flow.
- Mobile: no pinned scenes. Each verified screenshot remains next to its semantic chapter, school UI becomes a one-column composite, and controls retain at least 44 CSS pixels.
- Short viewports: pinned systems are disabled through minimum-height media queries.

## Accessibility

- Semantic document order exists independently of visual stages.
- `prefers-reduced-motion` disables scroll scrubbing, pinned layouts, ambient loops, and progress motion.
- `prefers-reduced-transparency` removes translucent chrome and decorative atmospheres.
- `prefers-contrast: more` promotes muted text and boundaries to the main text color.
- `prefers-color-scheme: dark` has an explicit token set.
- Locale buttons use `aria-pressed`; navigation uses `aria-current`; menus, links, FAQ controls, skip link, and focus rings remain keyboard accessible.
- Decorative shared stages are hidden from assistive technology while equivalent real screenshots and copy remain in semantic order.

## Assets

Approved assets live in `server/privacy-page/public/assets/`:

- `oneul-icon.png`
- `iphone-timeline.jpg`
- `iphone-ai.jpg`
- `ipad-timeline.jpg`
- `watch-timeline.jpg`
- `mac-week.jpg`

No temporary or downloaded assets are used.

## Content and CTA Editing

- Korean and English homepage copy: `server/privacy-page/public/content/oneul-home.js`
- Progressive-enhancement Korean fallback and semantic structure: `server/privacy-page/public/index.html`
- Mac download URL and platform CTA behavior: `MAC_DOWNLOAD_URL` at the top of `server/privacy-page/public/app.js`
- Product screenshots, logo, and icon: `server/privacy-page/public/assets/`
- Verified feature claims: `server/privacy-page/PRODUCT.md`

## Performance Notes

- No runtime dependencies or framework bundle.
- One passive scroll listener and one animation-frame scheduler.
- Layout measurement is never performed inside the normal scroll render path.
- All images declare intrinsic dimensions; the hero image alone is preloaded.
- Non-critical screenshots use lazy loading and asynchronous decode.
- Continuous atmosphere motion runs only while the hero is active.
- Heavy pinned layouts are removed on mobile, short screens, and reduced motion.

## Test Commands

```bash
cd "server/privacy-page"
node --check public/content/oneul-home.js
node --check public/app.js
node test-platform-cta.mjs
wrangler deploy --dry-run --outdir /tmp/oneul-home-dist
wrangler dev
```

## Known Limitations

- `MAC_DOWNLOAD_URL` is intentionally empty until a signed and notarized public Mac build exists.
- No App Store or direct-download link is published yet, so the CTA leads to truthful release information.
- The site has no approved absolute production origin, so canonical metadata is omitted rather than guessed.
