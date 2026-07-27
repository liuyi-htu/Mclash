# Release Process

Mclash releases are produced by `.github/workflows/manual-build.yml`.

After a successful build from `main`, a version higher than the repository's
current version is persisted to `mclash/pubspec.yaml` and the manual build
form's pre-filled version. Equal, lower, and failed builds do not change the
stored version.

## Test Pre-releases

- Use the pre-filled version or enter a higher version such as `1.2.0+5`.
- Use `build_channel=test`.
- The workflow publishes signed test builds as GitHub Pre-releases (内测版)
  using the fixed `mclash-test` tag.
- The test tag is overwritten by newer signed test builds.
- Unsigned test builds only upload Actions artifacts.

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
