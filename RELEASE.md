# Release Process

Mclash releases are produced by `.github/workflows/manual-build.yml`.

After a successful build from `main`, the automatically calculated version is
persisted to `mclash/pubspec.yaml`. Failed builds do not change the stored
version.

## Pre-releases

- Use `build_channel=prerelease`.
- The workflow publishes signed builds as GitHub Pre-releases (预发布版) using
  the future official version tag, such as `mclash-v1.8`.
- The same version tag is updated by newer signed pre-release builds.
- Unsigned pre-release builds only upload Actions artifacts.
- The pre-release major/minor version is calculated automatically from the
  latest official release. After official `v1.7`, every pre-release uses
  `v1.8`; successive builds overwrite the same `mclash-v1.8` Release. After
  official `v1.9`, the next pre-release is `v2.0`, not `v1.10`.
- Repeated builds of the same pre-release keep the same Flutter build number.
- The build number increases once only when a new official release starts the
  next pre-release version.

## Official Releases

- Use `build_channel=release`.
- The workflow derives the release tag automatically from the latest official
  release.
- The matching pre-release is promoted in place by changing Release metadata
  only.
- Existing official Releases are refused and never overwritten.
- Promotion does not rebuild or replace the APK, checksum file, or tag target.

Every build uploads `SHA256SUMS`. Verify downloaded APKs with:

```bash
sha256sum -c SHA256SUMS
```
