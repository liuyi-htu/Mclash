# Mclash Android build

Mclash is an independently developed and maintained Android proxy client built
with Flutter, Android VPN Service, mihomo, and HevSocks5Tunnel.

Current pinned build inputs:

| Item | Version |
| --- | --- |
| App name | `Mclash` |
| App package | `com.liuyihtu.mclash` |
| App source directory | `mclash` |
| Official build entry | `.github/workflows/manual-build.yml` |
| Flutter | `3.32.8` |
| Gradle | `8.10.2` |
| Java | `17.0.12+7` in GitHub Actions |
| Android minSdk | `24` |
| Android NDK | `27.2.12479018` |
| mihomo | GitHub Actions resolves the latest stable release automatically |
| HevSocks5Tunnel | `c6e4c72246fb0f20bda299f0efc7814bb3098d57` |

## Project Scope

This repository contains the Mclash Android package and reproducible build
workflow. Main components:

- Mclash Flutter UI for profile management and VPN start/stop;
- official prebuilt mihomo Android executable packaged as `libmihomo.so`;
- HevSocks5Tunnel built with Android NDK and packaged as native JNI/tun2socks;
- per-app proxy filtering and Quick Settings tile support;
- reproducible GitHub Actions build and release workflow;
- release signing externalized to local files or GitHub Secrets.

## Build Entry

GitHub Actions is the official complete build pipeline for this repository.
The project keeps build logic in GitHub Actions instead of a standalone local entry. Normal
users should download APKs from [Releases](https://github.com/liuyi-htu/Mclash/releases).

Repository layout:

```text
.
+-- mclash/
+-- .github/workflows/manual-build.yml
+-- .github/workflows/security-check.yml
+-- README.md
+-- RELEASE.md
+-- CONTRIBUTING.md
+-- SECURITY.md
+-- LICENSE
`-- NOTICE
```

Developers who want to reproduce the build locally can follow the commands in
[manual-build.yml](.github/workflows/manual-build.yml) step by step: install the
pinned Flutter, Java, Android SDK Build Tools and NDK versions; download and
verify mihomo; build HevSocks5Tunnel; copy native libraries into `jniLibs`; run
`flutter pub get`, `flutter analyze`, and `flutter build apk --release`.

The workflow is kept explicit so the build can be reviewed directly in GitHub.

## Release signing

Release builds are unsigned by default. The project no longer uses Android's
debug signing config for release APKs. Ordinary developers do not need my
signing key to build this project. Official release APKs must be signed with
the builder's own private keystore.

My official signing key is kept only in a local secure backup and in GitHub
Actions repository secrets. It is not committed to this repository.

Create your own keystore:

```bash
keytool -genkeypair \
  -v \
  -keystore release.jks \
  -storetype JKS \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias release \
  -dname "CN=Your Name, OU=Android, O=Your Org, L=City, S=State, C=US"
```

For local signing, create `mclash/android/key.properties` outside Git:

```properties
storeFile=/absolute/path/to/release.jks
storePassword=your-store-password
keyAlias=release
keyPassword=your-key-password
```

If this file is missing, incomplete, or points to a missing keystore, Gradle
skips the release signing config instead of failing configuration. The build can
still produce an unsigned release APK for local testing.

For GitHub Actions signing, configure these repository secrets:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

`ANDROID_KEYSTORE_BASE64` must be the base64-encoded keystore file. Example:

```bash
base64 -w 0 release.jks
```

On Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks")) | Set-Clipboard
```

Add the four values under **Settings** -> **Secrets and variables** ->
**Actions**. The workflow signs only when all four secrets are present. It
decodes the keystore to `$RUNNER_TEMP/release.jks`, writes a temporary
`mclash/android/key.properties`, builds, and deletes both temporary files
at the end.

Never commit or publish `.jks`, `.keystore`, `key.properties`, passwords, or
Base64-encoded signing material.

## GitHub Actions build

Open **Actions** -> **Manual APK Build** -> **Run workflow**.

The workflow uses:

- `ubuntu-24.04`;
- Flutter `3.32.8`;
- Temurin Java `17.0.12+7`;
- Android NDK `27.2.12479018`;
- latest stable mihomo release, excluding draft, prerelease, alpha, beta, rc,
  and nightly tags;
- read-only `contents: read` permission for the build job;
- `contents: write` only for release publishing;
- a repository-scoped write deploy key only for synchronizing the app version.

Choose `build_channel=prerelease` to build the next pre-release or
`build_channel=release` to promote it to official. The version is calculated
automatically. Architecture, ABI splitting, Hev handling, signing detection,
and publishing behavior are fixed internally. Builds target ARM64
(`arm64-v8a`) only; ARMv7 APKs are not generated.

After a successful build from `main`, the automatically calculated version is
written back to `mclash/pubspec.yaml`. Repeated builds for the same pre-release
keep the same Flutter build number. The build number increases once only when
the latest official release advances and starts a new pre-release version.
Failed builds do not change it. The deploy key private half is stored only in
the `VERSION_SYNC_DEPLOY_KEY` Actions secret.

Pre-release builds use the same version tag as the future official release.
For example, `1.8.0+14` uses `mclash-v1.8`. Signed builds of the same pre-release
version update that GitHub Pre-release (预发布版) and overwrite its APK files plus
`SHA256SUMS`; unsigned builds only upload an Actions artifact. The pre-release
major/minor version is calculated only from the latest official release. For
example, after official `v1.7`, every pre-release automatically uses `v1.8`;
successive builds keep the same app version and update the same
`mclash-v1.8` Release. Minor versions roll over after 9, so official `v1.9`
starts the `v2.0` pre-release instead of `v1.10`.

Choosing the `release` channel calculates the same next-version tag from the
latest official release. It does not rebuild or replace any files; it only
changes the matching Pre-release to an official Release and marks it Latest.
An existing official Release is never overwritten.

Artifacts are named by version and signing state, for example
`Mclash-for-Android-v1.8-signed`.
Release APK filenames include the version, ABI, and signing state.

Every build includes `SHA256SUMS` generated from the final APK filenames.
Verify downloads with:

```bash
sha256sum -c SHA256SUMS
```

Ordinary users should prefer official signed APKs from `mclash-v*` releases.

## Android permissions and network policy

`QUERY_ALL_PACKAGES` is used to list launchable installed apps for per-app proxy
include/exclude rules. Removing it would prevent the app selector from showing a
complete app list on modern Android versions.

The app does not enable global cleartext traffic. It uses Network Security
Config to keep cleartext disabled by default and allow only localhost/loopback
addresses needed for the local mihomo proxy and controller.

The IPv6 switch in VPN settings controls both mihomo's top-level `ipv6` option
and the Android VPN/HevSocks5Tunnel IPv6 address and routes. DNS-specific
behavior remains controlled by the imported profile's `dns` section.

## Third-party licenses

See [NOTICE](NOTICE). In short:

- mihomo: GPL-3.0;
- HevSocks5Tunnel: MIT.
