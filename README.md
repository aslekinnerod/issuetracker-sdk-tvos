# Issuetracker SDK for tvOS

Drop-in issue reporter for Apple TV apps. Press and hold Play/Pause on
the Siri Remote for 2 seconds, or call `Issuetracker.report()` —
capture a screenshot and file an issue directly into a pre-configured
Issuetracker project.

## Install

### Swift Package Manager

```swift
.package(url: "https://github.com/aslekinnerod/issuetracker-sdk-tvos.git", from: "0.1.0")
```

## Quickstart

```swift
import IssuetrackerTVSDK

@main
struct MyApp: App {
  init() {
    Issuetracker.configure(apiKey: "it_...")
  }
  var body: some Scene { WindowGroup { ContentView() } }
}
```

If your app knows who the user is, call `Issuetracker.identify(name:)`
after login — text entry with the remote is slow, and this skips the
one-time name prompt entirely.

## Trigger model

The Siri Remote has no shake and no touch long-press, so the tvOS
trigger is **hold Play/Pause for 2 seconds**, exposed under the same
`longPressToReport` flag as the other SDKs. The Menu/Back button is
never intercepted. Apps with heavy playback surfaces can pass
`longPressToReport: false` and wire `Issuetracker.report()` to a
settings row instead.

A held button is invisible UX, so the SDK ships a one-time onboarding
panel that teaches the trigger: opt in with
`configure(apiKey:showOnboarding: true)`, re-show it any time via
`Issuetracker.showOnboarding()`. Same semantics as sdk-ios.

## Differences from sdk-ios

Deliberately not included on this platform:

- **Shake to report** — no accelerometer in the trigger model.
- **Crash reporting** — MetricKit does not exist on tvOS.
- **Video recording & screenshot annotation** — touch-dependent flows.

Everything else is at parity: key-prefix environment routing, the
one-way TERMINATED lifecycle (ADR-0003 Decision 9), tester attestation
/ testers-only mode (ADR-0005), breadcrumbs, reporter identity, and
the spec'd progress components (geometry ×2 for the 10-foot UI,
behaviour rules unchanged).

## Accessibility

The hold-Play/Pause trigger is a plain button hold — unlike shake or
two-finger long-press on the other platforms it is neither motion
actuation (WCAG 2.5.4) nor a multipoint gesture (2.5.1). It is still
an invisible, timing-dependent action: it can't be discovered without
being taught, some users can't hold a button for 2 seconds, and
remote input behaves differently while VoiceOver or Switch Control is
running.

If you enable the trigger, you should **also** expose a visible,
focusable control in your own UI that calls `Issuetracker.report()` —
for example a "Report a bug" row in your settings or help screen:

```swift
Button("Report a bug") {
  Issuetracker.report()
}
```

You should also offer a user-facing setting to disable the hold
trigger (re-run `configure` with `longPressToReport: false`), both
for accessibility reasons and because a held Play/Pause can conflict
with playback-heavy UIs.

The SDK's own UI is fully focus-engine navigable, supports VoiceOver
labels and submit-progress announcements, scales its type with the
system text size where tvOS allows it, and respects Reduce Motion.

## Full documentation

API reference, triggers, TERMINATED behavior, identity flow,
breadcrumbs, and troubleshooting — see
**[docs.issuetracker.no/sdk/tvos](https://docs.issuetracker.no/sdk/tvos)**.

## Requirements

- tvOS 17.0+
- Swift 5.9+
- Xcode 15+

## License

MIT
