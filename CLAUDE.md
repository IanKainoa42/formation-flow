# FormationFlow Development Guide

## Common Commands

### Build
```bash
# Build the app
xcodebuild -scheme FormationFlow build

# Clean build
xcodebuild -scheme FormationFlow clean
```

### Run
Open `FormationFlow.xcodeproj` in Xcode 15+, select iPad as target device, and press Run (⌘R).

### Tests
No unit tests currently exist. The README lists testing for collision detection and path calculations as a next step.

### Linting
No linter is configured. This is a pure SwiftUI project with no external dependencies.

## Architecture

### Core Layers

**Models** (`Models.swift`)
- `CourtConstants`: Standard 52ft × 30ft cheerleading court with 12px-per-foot grid
- `AthleteRole` enum: base, flyer, spotter, backspot, tumbler (each with distinct colors)
- `PersistenceManager`: Singleton managing all formation save/load via UserDefaults with JSON encoding
- `Formation`: Container for athletes and metadata (name, notes, ID)
- `Athlete`: Position, role, and label data

**Views** (Feature-based organization)
- `FormationFlowApp.swift`: App entry point with NavigationStack and PersistenceManager environment
- `FormationListView.swift`: Formation CRUD (create, rename, duplicate, delete)
- `FloorGridView.swift`: Main editor with drag-drop placement, state caching for collision detection
- `FloorCanvasView.swift`: Canvas-based rendering of the court and athletes
- `TransitionViews.swift`: Transition selection, animation player with timing/speed controls
- `TimingControlsView.swift`: Per-athlete move timing controls
- `AthleteDetailPanel.swift`: Athlete role, label, and detail editing
- `FormationThumbnailView.swift`: Formation preview thumbnail

### Key Design Patterns

- **PersistenceManager as singleton**: Centralized state with debounced saves (0.5s delay) to UserDefaults
- **State caching**: FloorGridView caches collision detection results (`cachedCollisionIds`, `cachedCollisionCount`) for performance
- **Canvas rendering**: Uses SwiftUI Canvas for efficient court and path visualization
- **EnvironmentObject**: PersistenceManager passed to all views via environment

## Tech Stack

- **Swift 5.9+** with SwiftUI
- **iOS 17+**, iPad optimized
- **No external dependencies**
- **Xcode 15+** for development

## Important Features

- **Formation Management**: Create, save, load, rename, duplicate, delete formations via UserDefaults
- **Drag-drop Placement**: Smooth athlete positioning with collision detection and path visualization
- **Transition Animation**: Play/pause/scrub/speed control with per-athlete timing
- **Path Visualization**: Direction arrows and collision detection (red highlight when paths cross)
- **Court Grid**: 52ft × 30ft standard cheerleading court with athlete role colors

## Next Steps from README

- [ ] Unit tests for collision detection and path calculations
- [ ] iPad landscape-optimized layout
- [ ] Export formation as image
- [ ] Keyboard shortcuts
