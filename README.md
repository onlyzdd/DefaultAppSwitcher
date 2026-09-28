# Default App Switcher

A native macOS utility (Swift + SwiftUI, macOS 13+) for choosing which app opens each file type.

- **Common Types:** about 60 everyday extensions (text and code, documents, images, audio, video, archives, web), each showing its current default app. Pick another app from a row's menu to change it. You can also type any other extension in the filter field and change it the same way.
- **Drop File:** drop any file to detect its extension and Uniform Type Identifier, choose an app, and click **Apply to All**.

Changes apply to every file of that type for your user account. The app uses only Apple's own LaunchServices APIs (`NSWorkspace.setDefaultApplication(at:toOpen:)`, falling back to `LSSetDefaultRoleHandlerForContentType`). It has no third-party dependencies.

## Download

Get the latest build from **Releases**, or from the **Artifacts** section of any run in the **Actions** tab.
Builds are ad-hoc signed, not notarized. The first time you open one, go to **System Settings ▸ Privacy & Security ▸ Open Anyway**.

## Build locally

```sh
brew install xcodegen
xcodegen generate
open DefaultAppSwitcher.xcodeproj
```

See [SETUP.md](SETUP.md) for the full Xcode setup, the entitlements (App Sandbox must be off), and CI details.
