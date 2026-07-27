# Release Process

Mclash releases are produced by `.github/workflows/manual-build.yml`.

After a successful build from `main`, a version higher than the repository's
current version is persisted to `mclash/pubspec.yaml` and the manual build
form's pre-filled version. Equal, lower, and failed builds do not change the
stored version.

## Pre-releases

- Use the pre-filled version or enter a higher version such as `1.2.0+5`.
- Use `build_channel=prerelease`.
- The workflow publishes signed builds as GitHub Pre-releases (预发布版) using
  the future official version tag, such as `mclash-v1.8`.
- The same version tag is updated by newer signed pre-release builds.
- Unsigned pre-release builds only upload Actions artifacts.
- The pre-release major/minor version must be newer than the latest official
  release. For example, after official `v1.7`, use `1.8.0+14` or newer.

## Official Releases

- Set `version` to a complete patch-zero Flutter version. The next version
  after `1.0.0+1` is `1.1.0+3`.
- Use `build_channel=release`.
- The workflow derives the release tag automatically: `1.1.0+3` becomes
  `mclash-v1.1`.
- The matching pre-release is promoted in place by changing Release metadata
  only.
- Existing official Releases are refused and never overwritten.
- Promotion does not rebuild or replace the APK, checksum file, or tag target.

Every build uploads `SHA256SUMS`. Verify downloaded APKs with:

```bash
sha256sum -c SHA256SUMS
```
