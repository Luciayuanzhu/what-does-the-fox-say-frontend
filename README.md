# What Does the Fox Say

`What Does the Fox Say` is an iOS speaking-practice application built around a reactive animated fox character. Users choose a native language, a target practice language, and a fox persona. The app then supports realtime speaking practice, animation-driven character reactions, and a persistent session history with transcript, summary, and feedback.

## Project Goals

- Provide a playful, character-first speaking practice experience.
- Preserve every finished session as a reviewable learning artifact.
- Support anonymous device-based persistence without a traditional login flow.
- Keep the UI intentionally lightweight while still using native Apple frameworks for accessibility, lifecycle handling, audio, and networking.

## Frameworks Used

This project does **not** depend on any third-party runtime frameworks. The application is built primarily on Apple frameworks:

- `SwiftUI`
  - Main interface framework for onboarding, home, settings, history, detail views, splash screen, and custom alerts.
- `UIKit`
  - Used for `AppDelegate`, `SceneDelegate`, and the `UIHostingController` bridge that hosts the SwiftUI root view.
- `Foundation`
  - Provides networking (`URLSession`), JSON encoding/decoding, date handling, file URLs, task scheduling, and `UserDefaults`.
- `AVFoundation`
  - Powers video playback, microphone capture, audio playback, audio session configuration, local recording, and clip looping.
- `Security`
  - Used by the device installation manager to persist the anonymous device identifier in Keychain.
- `Combine`
  - Used selectively in controller/view-model plumbing where published state is consumed by SwiftUI.

## High-Level Architecture

- `FoxRootView`
  - Application shell that decides when to show splash, onboarding, main UI, and custom rate prompts.
- `FoxAppViewModel`
  - Main coordinator for app state, profile syncing, realtime speaking, history, and session lifecycle.
- `GeminiLiveClient`
  - Realtime audio/websocket client responsible for microphone capture, playback audio, transcript callbacks, and conversation recording artifacts.
- `FoxAPIClient`
  - REST/websocket endpoint client for auth, profile, sessions, history, retry, delete, and sync status.
- `VideoPlaybackController`
  - Dual-player video controller for fox idle loops, speaking loops, and one-shot interaction clips.
- `FoxHistoryPushClient`
  - Lightweight websocket client for history red-dot and processing-state updates.

## Important User Flows

### Onboarding

1. Choose a native language.
2. Choose a practice language.
3. Choose a fox persona.

These values are stored locally and synchronized to the backend profile when the API base URL is configured.

### Realtime Practice

1. The app creates a practice session.
2. A realtime websocket is opened.
3. Microphone capture starts.
4. The fox switches between idle and speaking animations based on live audio responses.
5. When the session ends, the app uploads audio fallback data and finalizes the session.

### Session Review

Each saved session can display:

- `transcript`
- `summary`
- `feedback`

The history list also supports unread markers, retry for failed items, and delete actions.

## Local Persistence

The app stores the following locally:

- anonymous device identifier in Keychain
- onboarding-complete flag
- local profile (native language, target language, persona)
- review prompt counters
- initial launch date for `Settings.bundle`

## Settings.bundle

The project includes a `Settings.bundle` so the system Settings app can show:

- developer names
- initial launch timestamp

Defaults are registered at launch by `AppDelegate`.

## Logging

The app intentionally emits structured debug logs for:

- lifecycle transitions
- auth and profile sync
- realtime websocket state
- audio capture/playback
- session creation/finalization
- history sync and detail fetching

These logs are meant to make the application understandable to a third-party reviewer during testing.

## Notes for Reviewers

- The project is intentionally anonymous-auth based.
- Realtime speaking depends on a configured backend URL and websocket service.
- No third-party UI, audio, or networking frameworks are required by the app runtime.
