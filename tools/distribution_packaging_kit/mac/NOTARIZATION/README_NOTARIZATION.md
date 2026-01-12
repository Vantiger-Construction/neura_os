# macOS Zip + Notarization Checklist (Distribution outside TestFlight)

This is for distributing your macOS build via website/GitHub.

## You need
- Apple Developer Program membership
- Developer ID Application certificate (Keychain)
- (Optional) Developer ID Installer cert (for pkg)
- Xcode installed (for `notarytool`)
- An app-specific password or keychain profile for notarization

## Build
1) `flutter build macos --release`
2) Locate `.app` at:
   `build/macos/Build/Products/Release/Neura Companion.app` (name may vary)

## Codesign (deep)
- Sign frameworks + app bundle.
- Use hardened runtime.
- Example script included: `sign_and_notarize.sh`

## Package
Recommended: ZIP the .app (not DMG first)
- `ditto -c -k --keepParent "Neura Companion.app" "Neura_Companion_macOS.zip"`

## Notarize
- `xcrun notarytool submit Neura_Companion_macOS.zip --keychain-profile "AC_NOTARY" --wait`
- If accepted, staple:
  - `xcrun stapler staple "Neura Companion.app"`

## Validate
- `spctl --assess --verbose "Neura Companion.app"`
- Fresh machine test (or new macOS user)

## Common gotchas
- Unsigned nested frameworks
- Missing hardened runtime
- Changing bundle identifier between releases
- Not incrementing version/build numbers
