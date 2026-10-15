# Browser

A native macOS browser built with SwiftUI and WebKit.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```sh
xcodegen generate
xcodebuild -project Browser.xcodeproj -scheme Browser -configuration Debug -derivedDataPath DerivedData build CODE_SIGNING_ALLOWED=NO
open DerivedData/Build/Products/Debug/Browser.app
```

## Contributing

See the [contributing guide](CONTRIBUTING.md). Pull requests can only be merged once you agree to the [Contributor License Agreement](CONTRIBUTOR_LICENSE_AGREEMENT.md).

## License

Copyright (C) 2026 Athas

Browser is licensed under the [GNU Affero General Public License v3.0](LICENSE) or later. Athas may also distribute it under other terms, such as through the Mac App Store.
