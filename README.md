# Harbor iOS

A native SwiftUI Stremio client for iPhone — inspired by [Harbor](https://github.com/harborstremio/harbor), rebuilt for iOS.

> Work in progress. Full sideloading instructions arrive with the first stable build.

## Development

```bash
brew install xcodegen   # macOS only
xcodegen generate
pod install
open Harbor.xcworkspace
```

CI builds an unsigned IPA on every push to `main` (Actions → Build IPA → artifact).
