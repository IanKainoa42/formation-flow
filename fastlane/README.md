fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios test

```sh
[bundle exec] fastlane ios test
```

Run tests

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight (openrsync-safe build)

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and upload to App Store (no submit; openrsync-safe build)

### ios ship_upload

```sh
[bundle exec] fastlane ios ship_upload
```

Build + upload binary to App Store Connect. Does NOT submit. (/ship Phase 2)

### ios ship_submit

```sh
[bundle exec] fastlane ios ship_submit
```

Submit an already-uploaded build for review, auto-release after approval. (/ship Phase 2)

### ios asc_build_status

```sh
[bundle exec] fastlane ios asc_build_status
```

Print latest App Store build status as JSON (read-only). Used by /ship pre-flight.

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Generate screenshots

### ios register_devices

```sh
[bundle exec] fastlane ios register_devices
```

Register devices

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
