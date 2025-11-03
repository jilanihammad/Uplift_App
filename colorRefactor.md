# Light Theme Color Alignment Plan

## 1. Audit Hard-Coded Colors
- Inventory widgets/services using literal `Color(...)` values (AutoListening toggle, home cards, progress chips, onboarding cards, `ProgressService`, etc.).
- For each location, decide whether the color should map to an existing Material palette token or needs a custom light-mode variant.

## 2. Introduce a Light-Theme Palette Extension
- Create a `ThemeExtension` (e.g., `AppPalette`) in `lib/config/theme.dart` that exposes a tonal surface progression and accent tones for light mode only (e.g., `surfaceLow`, `surface`, `surfaceHigh`, `accentPrimary`, `accentSecondary`).
- Populate the extension with:
  - Light-mode values aligned with a Material 3-inspired tonal elevation system (10/20/30% surface variants) and a refined accent pair.
  - Dark-mode values identical to current styling so the existing dark theme is unaffected.
- Attach the extension to the light and dark `ThemeData` via the `extensions` list; in widgets, target `surfaceHigh` for raised cards, etc.

## 3. Consume Palette Values in Widgets
- Replace hard-coded colors with lookups:
  - `Theme.of(context).extension<AppPalette>()?.surfaceHigh` for cards, `surfaceLow` for chips, etc.
  - `Theme.of(context).extension<AppPalette>()?.accentPrimary` for CTAs/toggles, `accentSecondary` for secondary emphasis.
- Continue to branch on `brightness` only when a component needs different behavior per theme.

## 4. Update Services and Helpers
- Refactor helpers like `ProgressService.getConsistencyColor()` to pull colors from the theme extension (pass `BuildContext` or expose a context-aware facade); ensure they honor the tonal elevation/accents for light mode.
- Update typography defaults in `theme.dart` to use a modern, premium look (e.g., `GoogleFonts.interTextTheme().apply(bodyColor: colorScheme.onSurface, displayColor: colorScheme.onSurface)`), and verify `onSurfaceVariant` is used for secondary text.
- Ensure any utility that returns background/gradient colors leverages the new palette tokens.

## 5. Testing and Verification
- After refactoring each component, verify:
  - Light theme visuals align with the Material 3 tonal elevation cues (muted surfaces, subtle depth, premium accent usage).
  - Dark theme renders identically to current UI (no regression).
- Run through high-traffic screens (home dashboard, toggles, onboarding) in both modes; capture before/after screenshots to confirm readability and accent consistency.

- Document the palette usage in `theme.dart` (including tonal elevations, accent strategy, typography) for future reference.
- Consider structuring the palette so a future Material You seed (`ColorScheme.fromSeed(seedColor: AppPalette.primarySeed)`) can drive the light theme without major refactor.
- Optional: add linters/docs discouraging new hard-coded colors in UI components; monitor QA telemetry to catch unintended regressions.
