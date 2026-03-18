
**Learning:** Icon-only playback controls (e.g., play, pause, reset, loop toggles) in SwiftUI require explicit `.accessibilityLabel` modifiers. Without them, screen readers like VoiceOver just announce "button", leaving visually impaired users guessing. Furthermore, stateful toggles (like loop on/off) benefit greatly from `.accessibilityValue` to communicate the current state.

**Action:** Whenever implementing icon-only buttons for playback or transport controls in this application, always attach an `.accessibilityLabel` summarizing the action, and use `.accessibilityValue` if it is a toggle to clarify the active/inactive state.
