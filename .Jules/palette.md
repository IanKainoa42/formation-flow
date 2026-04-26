## 2024-05-14 - Add accessibility hints to PortraitActionBar buttons
**Learning:** Found an accessibility pattern where icon-only buttons possessed `.accessibilityLabel` and `.help` modifiers but lacked the complementary `.accessibilityHint`. This creates an inconsistent experience for VoiceOver users who wouldn't get the same explanatory context that macOS/iPadOS pointer users get via the `.help` tooltip. We resolved this by adding matching `.accessibilityHint` modifiers to ensure parity.
**Action:** When adding or verifying accessible controls for icon-only buttons, systematically ensure that they contain both an `.accessibilityLabel` and an `.accessibilityHint`, specifically mirroring the `.help` text if present, to provide robust contextual information to assistive technologies.

## 2024-05-15 - Refine Accessibility Hints
**Learning:** Adding `.accessibilityHint` strings that simply repeat the `.accessibilityLabel` text is a known accessibility anti-pattern. Apple's Human Interface Guidelines instruct developers to never repeat the label in the hint, as this makes VoiceOver read the same text twice sequentially, creating a verbose and degraded experience.
**Action:** Always write unique, descriptive `.accessibilityHint` strings that provide additional context about the *result* of the action (e.g., "Removes this waypoint...") rather than copying the `.accessibilityLabel` text directly.
## 2026-04-20 - Mirror a11y hints and tooltips for icon buttons
 **Learning:** In multi-platform SwiftUI apps (macOS/iPadOS pointer + VoiceOver), it is a reusable UX pattern to have `.help()` text exactly mirror the `.accessibilityHint()` text for icon-only buttons to ensure consistent contextual information across interaction modes.
 **Action:** Always verify that `.help()` modifiers on icon buttons provide the same level of descriptive context as their `.accessibilityHint()` counterparts.
