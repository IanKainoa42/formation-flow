
**Learning:** Icon-only playback controls (e.g., play, pause, reset, loop toggles) in SwiftUI require explicit `.accessibilityLabel` modifiers. Without them, screen readers like VoiceOver just announce "button", leaving visually impaired users guessing. Furthermore, stateful toggles (like loop on/off) benefit greatly from `.accessibilityValue` to communicate the current state.

**Action:** Whenever implementing icon-only buttons for playback or transport controls in this application, always attach an `.accessibilityLabel` summarizing the action, and use `.accessibilityValue` if it is a toggle to clarify the active/inactive state.

**Learning:** Manually overriding `.accessibilityValue` for standard SwiftUI `Slider` components breaks the native VoiceOver experience. Native `Slider` components correctly announce their percentages or bounded values by default.

**Action:** DO NOT manually override `.accessibilityValue` on `Slider` components; let them use their native accessible behaviors.

## 2024-03-XX - [Loading States in Primary Action Buttons]

**Learning:** Swapping out a primary action button for a standalone `ProgressView` during asynchronous operations (like purchases) causes jarring UI layout jumps and completely removes the user's context of what action is being performed. It also causes screen readers to lose focus unexpectedly.

**Action:** Embed loading states (e.g., `ProgressView`) directly *inside* the primary action button while disabling it. This maintains layout stability, preserves context, and allows for proper `accessibilityLabel` updates (e.g., changing from "Upgrade" to "Upgrading").

## 2024-03-XX - [Interactive Text Elements]

**Learning:** Custom tap gestures on text elements (like `.onTapGesture` on a `Text` view) are completely missed by VoiceOver users unless explicitly marked as interactive. This leaves users unaware that they can tap the text to perform an action. Additionally, `.accessibilityHint` should describe the result of the action, not the interaction itself, as VoiceOver automatically adds "Double tap to activate" for elements with `.isButton` trait.

**Action:** Whenever using `.onTapGesture` on a non-interactive element like `Text`, always attach `.accessibilityAddTraits(.isButton)` so VoiceOver announces it as a button, and provide an `.accessibilityHint` (e.g., "Jumps to the next formation") to explain the result of the action.
