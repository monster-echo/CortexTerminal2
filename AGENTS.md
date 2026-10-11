# HarmonyOS UI layout

- Keep form and picker content aligned from the top, following the header in natural reading order. Do not vertically center functional controls inside full-height pages or sheets.
- Use remaining layout weight only for scrollable content or bottom-pinned actions. Reserve vertical centering for intentionally centered loading and empty states.
- For modal sheets, size the sheet explicitly and keep its content anchored to the top with safe-area insets applied only where the sheet can reach system bars.
- Keep related modal states under one presentation owner. Do not stack native `bindSheet` instances attached to unrelated component trees; switch modal content or render the child selection layer inside the owning sheet so selection cannot activate underlying pages.
