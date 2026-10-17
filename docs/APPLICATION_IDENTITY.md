# Application identity

The bundle identifier is **`io.github.corbeusultra.ClearCommandTab`**. It is declared in `Resources/Info.plist` and in the shared runtime constant `ApplicationIdentity.bundleIdentifier`; integration checks require them to match. Signing and fixture/preview packaging read the metadata instead of maintaining another production identifier.

The reverse-domain-shaped name provides a namespace based on the author's public GitHub handle. It is not a website address, network connection, password or signing key. The display name **ClearCommandTab** is a separate field.

## What uses it

- macOS identifies the app bundle by this value, including when locating or launching an app.
- `UserDefaults.standard` stores this app's persistent preferences in its application domain. Changing the identifier changes that domain.
- Code signing includes a code-signing identifier and a designated requirement. The build script uses the bundle identifier as its signing identifier. A certificate alone does not make two different identifiers the same app.
- macOS privacy decisions depend on the application identity/signing requirements. Existing Accessibility approval cannot simply be copied to a new identity by moving preference files.
- Launch-at-login registration is managed by `SMAppService` for the app. Its state is not the same thing as an ordinary saved checkbox preference.
- The app also uses its namespace for internal reopen notifications and diagnostic logs. These are our own conventions, rather than additional macOS bundle fields.

## Pre-publication migration — 2026-10-17

The author selected this new identifier. During the local update, the previous preference domain is backed up privately and missing preference values are copied into the new domain before the installed app launches. Existing destination values are preserved. The old preference domain is retained as a fallback backup; public runtime code does not keep reading it.

The private migration materials remain under ignored `.local/identity-migration/`; they are excluded from publication. This is a one-time migration for the current development installation, not a claim that fresh installations contain old settings.

The migration does not edit, reset or copy macOS privacy records. The user may need to enable the newly identified installed app in **System Settings → Privacy & Security → Accessibility** (named **Device Control and Data Access** on some macOS versions). Login launch and the separate system menu-bar allowance may also need to be enabled again if previously configured. The app reports its actual GUI permission/interception state after launch; a signed bundle or a terminal trust check does not establish that permission.

Future ordinary updates should keep this identifier stable. A new version number or display name does not require another identity change.

## Apple references

- [CFBundleIdentifier](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleIdentifier).
- [Code signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
- [Main-app login service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp).
