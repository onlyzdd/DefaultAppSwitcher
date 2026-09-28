# Default App Switcher: Xcode Setup

> **Shortcut:** with [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed
> (`brew install xcodegen`), run `xcodegen generate && open DefaultAppSwitcher.xcodeproj`
> in this folder. That applies everything in steps 1–3 automatically, from `project.yml`.

Requires Xcode 15 or later. Minimum deployment target: macOS 13 Ventura.

## 1. Create the project

1. In Xcode, choose **File ▸ New ▸ Project… ▸ macOS ▸ App**.
2. Fill in the options:
   - Product Name: `DefaultAppSwitcher`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: None. Leave "Include Tests" unchecked.
3. Select the target, open **General ▸ Minimum Deployments**, and set **macOS 13.0**.

## 2. Add the source files

1. Delete the template's `ContentView.swift`, `DefaultAppSwitcherApp.swift` and `Assets.xcassets` (Move to Trash).
2. Drag the `DefaultAppSwitcher/` source folders from this package into the project navigator.
   Check **Copy items if needed** and **Create groups**, and make sure the app target is ticked.

```
DefaultAppSwitcher/
├── DefaultAppSwitcherApp.swift            App entry, fixed-size single window
├── Assets.xcassets/AppIcon.appiconset     App icon, 16–1024 px
├── Models/Models.swift                    FileTypeInfo, AppHandler, common-types catalog
├── Services/LaunchServicesManager.swift   Native LaunchServices bridge
├── ViewModels/
│   ├── FileTypeViewModel.swift            "Drop File" tab state
│   └── CommonTypesViewModel.swift         "Common Types" tab state
└── Views/
    ├── ContentView.swift                  Segmented control switching the two tabs
    ├── DropFileView.swift                 Drop zone → Picker → Apply to All
    ├── DropZoneView.swift                 Hover-highlighting drop target
    ├── CommonTypesView.swift              Extension list with per-row default-app pickers
    └── VisualEffectBackground.swift       Behind-window translucency
```

## 3. Signing & Capabilities (the important part)

Select the target and open the **Signing & Capabilities** tab.

| Setting | Value | Why |
|---|---|---|
| **App Sandbox** | **Remove it** (click the 🗑 / ✕ on the capability) | LaunchServices won't let a sandboxed process rewrite the user's default-handler database. With the sandbox on, the call fails (often with `-54 permErr`) or is silently ignored. |
| **Hardened Runtime** | Keep it on, with **no exceptions ticked** | None are needed. The app doesn't use JIT, unsigned libraries, Apple Events, or protected resources. |
| Signing | "Sign to Run Locally", or your team with "Development" | Any signing works for local use. |

When you remove the capability, Xcode may delete or empty the entitlements file. Either result is fine.
If you'd rather keep a file, use the included `DefaultAppSwitcher.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

Then go to **Build Settings ▸ Code Signing Entitlements** and make sure the value points to that file
(`Support/DefaultAppSwitcher.entitlements`). If you deleted the file, clear the value.

### Info.plist

**No privacy keys are required.** The app reads only file-system metadata (extension and
type). It never reads file contents. Dragging a file in, or picking one in the open panel,
counts as user intent, so there's no TCC prompt.

Optional, under **Target ▸ Info**:

| Key | Value |
|---|---|
| `LSApplicationCategoryType` | `public.app-category.utilities` |
| `CFBundleDisplayName` | `Default App Switcher` |

Don't add `CFBundleDocumentTypes`. This app shouldn't show up as a handler itself.

## 4. Build and run (⌘R)

**Common Types tab:** about 60 everyday extensions, grouped by kind, each showing its current
default app. Pick another app in a row's menu and the change applies at once; a ✓ confirms it.
Type an extension that isn't listed (e.g. `.srt`) in the filter field to add it.

**Drop File tab:**

1. Drag a `.txt` file onto the drop zone. It shows `public.plain-text`.
2. Pick an app in **Open with**. The current default is labelled "(default)".
3. Click **Apply to All**, or press Return.
4. To verify, open **Get Info** on any `.txt` file in Finder and check **Open with**. You can also run:

   ```sh
   defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | grep -A3 plain-text
   ```

## Notes and limits

- **Scope:** "Global" means *for the current user account*. That's how macOS stores these
  defaults. Other user accounts aren't affected.
- **Deprecation warning:** Xcode warns that `LSSetDefaultRoleHandlerForContentType` has been deprecated since macOS 12.
  That's expected. It's only the fallback. The primary path is
  `NSWorkspace.setDefaultApplication(at:toOpen:)`, Apple's current supported API.
- **Dynamic types (`dyn.…`):** these appear when no installed app declares the extension.
  The app warns you because these associations are less reliable.
- **Protected types:** for a few types, especially web-related ones, macOS may show its own
  confirmation dialog. If the user declines, the app reports it and doesn't retry.
- **Distribution:** a non-sandboxed app can't go on the Mac App Store. Share it with a
  **Developer ID** signature and **notarization**
  (Product ▸ Archive ▸ Distribute App ▸ Direct Distribution).
- **Swift 6 / Xcode 16+:** the code is written to build cleanly with strict concurrency. The manager and view model
  are `@MainActor`, and NSWorkspace's callback is wrapped in a checked continuation.

## Building on GitHub Actions

`.github/workflows/build.yml` runs on every push to `main`, every pull request, and manual runs:

1. On a `macos-15` runner, it installs XcodeGen and generates the project.
2. It builds a universal (arm64 + x86_64) Release binary, ad-hoc signed, with Hardened Runtime.
3. It verifies the signature and prints the entitlements. `app-sandbox` should be `false`.
4. It uploads `DefaultAppSwitcher.zip` as a build artifact (**Actions ▸ run ▸ Artifacts**).
5. When you push a tag such as `v1.0.0`, it also creates a GitHub Release with the zip attached.

**Opening a CI build:** it's ad-hoc signed, not notarized, so Gatekeeper blocks the first
launch. Open it once, then go to **System Settings ▸ Privacy & Security ▸ Open Anyway**.
Or run `xattr -dr com.apple.quarantine DefaultAppSwitcher.app`.
To remove that step, add your Developer ID secrets and uncomment the notarization step in the workflow.
