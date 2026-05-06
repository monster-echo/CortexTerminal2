# Landing Page i18n: Chinese/English Language Switching

## Context

The GitHub Pages landing page (`landing/index.html`) is a self-contained static HTML file (706 lines) with all CSS and JS inline. All text is hardcoded in English. The project's Gateway Console (React SPA) already has full i18n support via i18next with `en`/`zh` locales.

## Approach

Pure JS + `data-i18n` attribute approach. Zero external dependencies. All logic stays in the single `index.html` file.

## Design

### Language Switcher

- Position: Navigation bar, `nav-links` area, first item (before "GitHub" link)
- Style: Matches existing `nav-btn` design language
- Display: Shows current language label (`EN` / `中文`)
- Behavior: Click toggles between English and Chinese

### Translation Mechanism

1. **`data-i18n="key"` attributes** on all translatable text elements
2. **Translation dictionary** as a JS object embedded in `<script>`:
   ```js
   const translations = { en: { ... }, zh: { ... } }
   ```
3. **`applyLang(lang)` function** that:
   - Reads translations for the given language
   - Iterates all `[data-i18n]` elements and replaces `textContent`
   - Updates `<html lang="...">`
   - Updates the language switcher button label

### State Persistence

- User's language preference stored in `localStorage` under key `lang`
- On page load: read from localStorage, fall back to `en`
- The "Copy" / "Copied!" button text also follows the active language

### Translatable Content

Approximately 30 text segments across:
- Nav links (Launch Console)
- Hero section (badge, title, subtitle, install hint, platform tags)
- Architecture section (heading, description, node names/roles)
- Features section (heading, description, 6 cards with titles + descriptions)
- Quick Start section (heading, description, 3 steps with titles + descriptions)
- CTA section (heading, description, button labels)
- Footer (copyright)

### Translation Style for Chinese

- Technical terms kept in English where appropriate (e.g., Gateway, Worker, JWT, SignalR, xterm.js, Docker)
- Natural, concise Chinese phrasing matching the original's tone
- Code snippets and commands remain unchanged

## Scope

- Single file: `landing/index.html`
- No changes to `landing/install.sh`
- No changes to `.github/workflows/gh-pages.yml`
- No new files or external dependencies
