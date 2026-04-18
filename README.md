# Plants

A small iOS app for keeping houseplants alive. Snap a photo, let the model suggest care intervals, and get nudged when something needs water or fertilizer. Built with SwiftUI + SwiftData for iOS 26.

<p align="center">
  <img src="docs/screenshots/01-needs-care.jpg" width="240">
  <img src="docs/screenshots/02-detail-overdue.jpg" width="240">
  <img src="docs/screenshots/03-history-calendar.jpg" width="240">
</p>

## Features

- **Photo-based identification.** Take or pick a photo of a plant; an LLM suggests a name, watering interval, light needs, fertilizer schedule, toxicity notes, and a care tip.
- **"Needs care" shortcut.** The main list pins plants that are due or overdue at the top with inline droplet / leaf buttons — tap to mark watered or fertilized without opening the plant.
- **Local notifications.** Reminders fire on the plant's schedule. The notification itself has a "Mark as watered" action so you can dismiss and record in one tap.
- **Care history calendar.** Each plant has a month-by-month calendar with a droplet on days it was watered and a leaf on days it was fertilized.
- **Same-day lockout.** Once you've watered a plant today, the button reads "Watered today" and is disabled — no accidental double-taps.

## Stack

- Swift 6 / SwiftUI / SwiftData
- `UserNotifications` for scheduled reminders with inline actions
- OpenRouter for the identification call (any Gemini-class model)
- XcodeGen to generate `Plants.xcodeproj` from `project.yml`

## Running it locally

1. Install Xcode 26+ and XcodeGen (`brew install xcodegen`).
2. Copy the secrets template and fill in your own key:
   ```
   cp Secrets.xcconfig.example Secrets.xcconfig
   # edit Secrets.xcconfig and set OPENROUTER_API_KEY
   ```
3. Regenerate the project and open it:
   ```
   xcodegen generate
   open Plants.xcodeproj
   ```
4. Select the **Plants** scheme and run on an iOS 26 simulator.

### Debug shortcuts

- Set the env var `PLANTS_DEBUG_SAMPLE_IMAGE=/absolute/path/to/image.jpg` on the scheme's Run action. A debug-only button appears on the Add Plant screen that uses that image instead of forcing you through the picker.
- On the plant detail view's ellipsis menu, `Simulate overdue (debug)` backdates `lastWatered` / `lastFertilized` so the plant immediately shows up in the "Needs care" section.

## Project layout

```
Plants/
  Models/            # SwiftData @Model types: Plant, CareEvent
  Services/          # NotificationService, GeminiClient, PlantCareActions
  Views/             # SwiftUI views (list, detail, add, history)
    Components/      # Small reusable views (PlantPhotoView, PlantRowView, PlantCareRowView)
  Resources/         # Asset catalog + Info.plist
project.yml          # XcodeGen source of truth
Secrets.xcconfig     # gitignored — your API key lives here
```

## License

MIT. Do what you like.
