# Startup Screen Improvements

## Experience Goals
- Present a warm, calming welcome that reflects Maya’s personality.
- Keep the look consistent with the app’s dark/light themes.
- Replace the stock loading spinner with a branded animation that feels intentional.

## Visual Design Recommendations
- **Background**: Use the app’s background color or a very soft gradient that adapts automatically to dark/light mode. Add faint, blurred blobs or wave shapes in secondary colors for depth.
- **Logo**: Center the Maya logotype or icon. If you have a vector mark, render it at ~120–160 px with gentle entrance animation (fade + slight scale-up).
- **Messaging**: Swap “Initializing…” for a friendlier tone, e.g.:
  - Primary: “Preparing Maya for you…”
  - Secondary: “A moment of calm while we get ready.”
- **Loader**: Replace `CircularProgressIndicator` with one of the following:
  - A custom animated ring using `TweenAnimationBuilder` that pulses in the accent color.
  - A Lottie JSON animation (wave, breathing orb, or particle field) that loops smoothly.
- **Layout**: Stack logo → spacing → headline → body text → loader. Use `AnimatedSwitcher` or `FadeTransition` so elements ease in.

## Implementation Steps
1. **Create a dedicated widget** (e.g., `HybridStartupSplash` in `lib/screens`) that accepts theme-aware colors and optional error/retry callbacks.
2. **Theme integration**:
   - Read `Theme.of(context)` for colors.
   - Use `ColorScheme.surfaceVariant` / `surfaceContainer` tokens for background cards so the screen blends with app theme.
3. **Add branding assets**:
   - Import the Maya SVG/PNG into `pubspec.yaml` if it isn’t already there.
   - Use `SvgPicture.asset` or `Image.asset` with high-quality filtering.
4. **Build the layout**:
   - Wrap the content in a `SafeArea` and `AnimatedSwitcher`.
   - Column alignment: `MainAxisAlignment.center`; pad horizontally (`EdgeInsets.symmetric(horizontal: 32)`), vertically to avoid cramped look.
   - Include a secondary text style (`theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)`).
5. **Add the animation**:
   - Option A: Implement a pulsing circle with `TweenAnimationBuilder<double>` and `ScaleTransition`.
   - Option B: Add a Lottie file (`lottie` package) and drop it below the texts.
6. **Handle error state**:
   - When initialization fails, crossfade to an error card with the same branding, an icon, the error message, and a “Try again” button.
7. **Integrate with existing startup flow**:
   - Update the `FutureBuilder`/state management to display the new widget for loading and error states.
   - Ensure transitions (`AnimatedSwitcher`) hide the splash once dependencies are ready.
8. **QA checklist**:
   - Verify dark/light rendering and typography.
   - Confirm animation plays smoothly on low-end devices.
   - Test error fallback messaging and retry button.
   - Run on tablet/large screens to ensure spacing scales.

## Optional Enhancements
- Play a soft looping ambient sound once initialization completes (respecting user settings).
- Add a subtle background particle effect using `CustomPainter` or `Rive` if performance allows.
- Localize the warm message for supported languages.

## Additional Engineering Guidelines

### 1. Performance & Perceived Speed
- Pre-cache the logo and any animation assets during install or the prior session using `precacheImage` (for raster/SVG via `SvgPicture.asset`) or by warming the `AssetManifest`.
- Keep Lottie JSON small (< 300 KB). Configure the widget with `repeat: true`, `animate: true`, `frameRate: FrameRate.max`, and `options: LottieOptions(enableMergePaths: false)` to avoid shader stalls.
- Add a safety net for slower devices: if animation initialization takes > 500 ms, fall back to a static logo fade so the splash never appears frozen.

### 2. Accessibility & Localization
- Wrap the top-level container in `Semantics(label: 'Preparing Maya for you')` so screen readers announce context immediately.
- Respect system “Reduce Motion” directives: check `MediaQuery.of(context).disableAnimations` and switch to static fades (no scale/breathing animations) when true.
- Move all splash copy into the intl localization files even if currently English-only, so translations can land without code edits.

### 3. Visual Polish
- Stagger entrance timings: 600–800 ms for the logo fade, 200–300 ms for text, and a 1.5–2 s loop for the breathing/pulsing animation to keep it soothing.
- Slightly desaturate the accent color for loaders, particularly in dark mode, to avoid harsh flicker.
- Add gentle depth under the logo via `PhysicalModel` or a soft `BoxShadow` so it reads well on OLED displays.

### 4. Transition Into Main UI
- When the app is ready, crossfade using `FadeTransition` or `SharedAxisTransition` (animations package) instead of an abrupt swap.
- Delay mounting the main router by ~100 ms after background initialization resolves so the fade finishes cleanly.
- If you use a gradient background, tween it into the scaffold’s surface color to preserve visual continuity.

### 5. Error & Retry UX
- Pair technical details with a friendly explanation, e.g., “Couldn’t reach our servers. Please check your connection.”
- Debounce retries: disable the button for the first 3 s to prevent accidental double taps.
- Log retry taps to analytics so startup reliability issues are traceable.
