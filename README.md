# Site Tape

An iPhone app for measuring an outdoor site with ARKit (LiDAR mesh when the phone has it).
Drop named pins on the ground, read live distances, see a top-down plan, and export JSON + PNG.

Built by GitHub Actions (`.github/workflows/ios.yml`): XcodeGen generates the project from
`project.yml`, then an unsigned compile, then a signed archive uploaded to TestFlight.

Signing secrets (names only): APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID,
APP_STORE_CONNECT_PRIVATE_KEY, IOS_DIST_CERT_P12, IOS_DIST_CERT_PASSWORD, IOS_PROVISIONING_PROFILE.
The profile must be an App Store profile named "Site Tape App Store CI" for xyz.empowertours.sitetape.
