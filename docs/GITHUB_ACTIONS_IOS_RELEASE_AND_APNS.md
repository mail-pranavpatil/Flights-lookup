# GitHub Actions iOS build, TestFlight upload, and APNs setup

This project is configured to build on a hosted GitHub `macos-latest` runner. You do not need to own a Mac. GitHub's macOS runner generates the Xcode project with XcodeGen, signs an archive, exports an IPA, and uploads it to TestFlight.

> **Important:** this is a release pipeline template. It will not succeed until you set the real App ID / bundle identifier and create matching Apple signing assets. It uploads to **TestFlight**, not directly to public App Store release. After TestFlight validation, submit the build for App Review in App Store Connect.

## 1. Before running the workflow

1. In Apple Developer → Certificates, Identifiers & Profiles, create or select an explicit App ID for `Where Is That Plane?`.
2. Choose a real bundle identifier you control, e.g. `com.yourcompany.whereisthatplane`. Do not use `com.example.WhereIsThatPlane` in production.
3. Enable **Push Notifications** for that App ID, save the changes, and create a new **App Store** provisioning profile for that App ID. The profile must include the Push Notifications entitlement.
4. Create an **Apple Distribution** certificate and export the certificate + private key as a password-protected `.p12`. Keep the `.p12` and password private.
5. In App Store Connect, make sure the app record exists for the same bundle identifier and the API key has an appropriate role (App Manager is a common choice for TestFlight uploads).
6. In the project, update the bundle identifier in all of these places so they match exactly:
   - `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER`
   - `Support/ExportOptions.plist` → key inside `provisioningProfiles`
   - `.github/workflows/ios-testflight.yml` → `com.example.WhereIsThatPlane` in the PlistBuddy command
7. In `project.yml`, set `PROVISIONING_PROFILE_SPECIFIER` to the exact display name of the App Store provisioning profile if you want to keep a fixed local default. The workflow also overrides it with the installed profile's actual name.

## 2. GitHub Actions secrets (7)

Open GitHub repository → **Settings → Secrets and variables → Actions → New repository secret**. Add these exact secret names:

| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_ISSUER_ID` | Your existing App Store Connect Issuer ID |
| `APP_STORE_CONNECT_KEY_ID` | Your existing App Store Connect API Key ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Full contents of your existing App Store Connect `AuthKey_*.p8` file (not base64) |
| `APPLE_TEAM_ID` | Your Apple Developer Team ID |
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded `.p12` file |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64-encoded `.mobileprovision` file |

You previously reported having the App Store Connect Issuer ID, API Key ID, Team ID, and `.p8` private key already. Reuse them if they are still active. The certificate-import action manages its temporary keychain on the hosted runner, so no separate keychain-password secret is required here. Never commit any `.p8`, `.p12`, passwords, provisioning profiles, or Base64 values to the repository.

### Create the Base64 values

Run these commands on any machine with `base64` available (on macOS, use the commands below). Do not paste the output into chat or commit it.

```bash
base64 -i AppleDistribution.p12 | tr -d '\n' | pbcopy
# Paste clipboard contents into APPLE_CERTIFICATE_BASE64

base64 -i WhereIsThatPlane_AppStore.mobileprovision | tr -d '\n' | pbcopy
# Paste clipboard contents into APPLE_PROVISIONING_PROFILE_BASE64
```

## 3. Run the build

1. Push the project to a GitHub repository.
2. Add the seven secrets above.
3. Open **Actions → Build and upload Where Is That Plane to TestFlight → Run workflow**.
4. The job builds on `macos-latest`, saves the IPA as a workflow artifact, and uploads the build to TestFlight.
5. Check the Actions log for errors, then App Store Connect → TestFlight for processing and testing.

The workflow also runs when you push a tag matching `ios-v*`, for example `ios-v0.1.0`. It does not automatically submit a public App Store release.

## 4. Apple Push Notifications (APNs) setup

**App Store Connect API key and APNs authentication key are different credentials.** Your existing App Store Connect `.p8` cannot be used as an APNs token-signing key unless it was specifically created as an APNs key; in normal setup, create a separate APNs key.

1. Open Apple Developer → **Certificates, Identifiers & Profiles → Keys**.
2. Create a key named `WhereIsThatPlane APNs` and enable **Apple Push Notifications service (APNs)**.
3. Download the APNs `.p8` file once and securely store it. Record its **Key ID**. Your Team ID is the same Apple Developer Team ID.
4. Confirm the app's explicit App ID has Push Notifications enabled and that the App Store provisioning profile was regenerated after enabling the capability.
5. Add APNs credentials to the **backend's secret manager**, not the iOS app bundle. If you later run the backend through GitHub Actions, use secrets named `APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_AUTH_KEY_P8` (full APNs `.p8` contents). The backend must also know the app bundle ID and the device's APNs token.
6. In the app, request notification permission and register with APNs; send the device token securely to your backend. The backend decides when a detected overhead event qualifies and sends a push to APNs.

The app's entitlements file includes `aps-environment=production` for App Store/TestFlight distribution. The profile must match that entitlement. For local development builds, a development-signed profile may require `aps-environment=development` instead.

### What is and isn't implemented

- Included here: XcodeGen project spec, GitHub macOS build/archive/export workflow, TestFlight upload step, signing placeholders, production APNs entitlement, and this setup guide.
- Not implemented by this workflow alone: an aircraft-monitoring backend, APNs provider server, device-token registration endpoint, route/destination enrichment, or reliable always-on location monitoring. Those need application/backend code and separate deployment configuration.
- iOS may limit background execution. The backend must do the aircraft monitoring and push delivery; the app should not rely on waking every few seconds to poll flight APIs.

## Official references

- GitHub: signing Xcode apps on hosted macOS runners — https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- Apple: App Store Connect API keys — https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api
- Apple: remote notification server and APNs — https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server
- Apple: User Notifications — https://developer.apple.com/documentation/usernotifications/
- Apple Actions: TestFlight upload action — https://github.com/Apple-Actions/upload-testflight-build
