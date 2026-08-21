# PindouAI Design

## Visual Direction

GitHub Pages adopts a "bead workshop field guide" direction. It uses the app's coral, teal, ink, and white palette, bold Chinese headings, registration-like grid lines, numbered workflow markers, real product screenshots, and artwork previews. The page should feel like a practical manual made by the product team, not a generic software landing page.

## Surface Strategy

- The first viewport identifies PindouAI, shows the real Android product, and exposes the Android APK download immediately.
- The page is organized around the user's sequence: install, create, use the artwork library, refine, manage, export, configure optional AI, and protect data.
- Real screenshots are always labeled as such. Feature explanations without a dedicated screenshot use factual text and existing artwork previews rather than fabricated interface mockups.
- Android is the primary story. Windows appears as a complete companion release, not a competing hero.

## Tokens

- Ink: `#211E1D`
- Paper: `#FFF9F5`
- White: `#FFFFFF`
- Coral: `#EF6253`
- Coral dark: `#B93630`
- Teal: `#167D76`
- Teal pale: `#DDF1EE`
- Yellow focus: `#F2C94C`
- Borders: `#E7DCD6`
- Corners: 4px for commands and utility surfaces, 8px for screenshots and repeated content items

## Interaction

- Sticky single-line navigation on desktop; compact brand and download action on mobile.
- Screenshot buttons open a native dialog lightbox and retain keyboard access.
- Scroll reveals use IntersectionObserver and stop under `prefers-reduced-motion`.
- All links and buttons expose visible focus, at least 44px interaction height, and stable dimensions.

## Responsive Rules

- No fixed-width content or horizontal scrolling.
- At 900px, multi-column guides collapse and the section navigation becomes horizontally scrollable without affecting the page width.
- At 620px, the hero retains the Android screenshot as a full-bleed background, CTAs become full-width, screenshot media uses stable aspect ratios, and feature rows become vertical.
