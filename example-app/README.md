# IssuetrackerTVExample

Minimal tvOS host app for exercising the SDK during development.

```sh
brew install xcodegen   # once
cd example-app
xcodegen generate
open IssuetrackerTVExample.xcodeproj
```

Run on an Apple TV simulator. In the simulator, hold the Play/Pause
button in the Remote window (Cmd+Shift+R to show it) for 2 seconds,
or use the on-screen button.

## E2E tests

The UI tests in `IssuetrackerTVExampleUITests` are the only automated
coverage of the 2-second hold, and CI runs them from this generated
project. To run them yourself:

```sh
xcodebuild test \
  -project IssuetrackerTVExample.xcodeproj \
  -scheme IssuetrackerTVExample \
  -destination "id=$(../scripts/tv-simulator-udid.sh)"
```

Resolve the destination with that script instead of hardcoding a device
name — `name=Apple TV` no longer matches anything Xcode creates.

The submission round-trip needs a real key, passed with the
`TEST_RUNNER_` prefix that Xcode strips on injection:

```sh
TEST_RUNNER_ISSUETRACKER_API_KEY=it_dev_... xcodebuild test ...
```

Without one it skips locally. In CI it must not: set
`TEST_RUNNER_REQUIRE_E2E_KEY=1` to turn a missing key into a failure,
and check the run with `../scripts/assert-test-results.sh <bundle> 3`,
which rejects skipped tests (`xcodebuild` reports them as successes).
