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
  the fixed `mclash-prerelease` tag.
- The pre-release tag is overwritten by newer signed pre-release builds.
- Unsigned pre-release builds only upload Actions artifacts.
- The pre-release major/minor version must be newer than the latest official
  release. For example, after official `v1.7`, use `1.8.0+14` or newer.

## Official Releases

- Set `version` to a complete patch-zero Flutter version. The next version
  after `1.0.0+1` is `1.1.0+3`.
- Use `build_channel=release`.
- The workflow derives the release tag automatically: `1.1.0+3` becomes
  `mclash-v1.1`.
- Existing official release tags are refused and never overwritten.
- Only signed builds create official GitHub Releases.

Every build uploads `SHA256SUMS`. Verify downloaded APKs with:

```bash
sha256sum -c SHA256SUMS
```
