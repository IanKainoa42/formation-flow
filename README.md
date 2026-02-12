# FormationFlow

Digital choreography tool for planning formation transitions without requiring the full team physically present.

## Features (MVP)

- ✅ Floor grid visualization (52ft × 30ft standard court)
- ✅ Drag-drop athlete placement
- ✅ 8 sample athletes with labels
- ✅ Basic transition animation
- 🔄 Coming Soon: Collision detection, save/load, animation player

## Tech Stack

- Swift 5.9+
- SwiftUI
- Canvas for rendering
- iOS 17+, iPad optimized

## How to Use

1. Clone this repo
2. Open in Xcode 15+
3. Select "iPad" as target device
4. Run (⌘R)
5. Tap "New Formation" to see the floor grid
6. Tap athletes to select, then drag to move

## Project Structure

```
Sources/FormationFlow/
├── FormationFlowApp.swift  - App entry point
├── Models.swift            - Formation & Athlete data
├── Views.swift             - Menu, FloorGrid, Drag UI
```

## Next Steps (Sauté Phase)

- [ ] Save/load formations to UserDefaults
- [ ] Collision detection algorithm
- [ ] Transition path calculation
- [ ] Animation player

## Next Steps (Slow Cooker Phase)

- [ ] TypeScript-style strict types
- [ ] Unit tests for collision detection
- [ ] iPad/landscape responsive layout
- [ ] Keyboard shortcuts
- [ ] Export formation as image

---

Built with ❤️ for CFSD
