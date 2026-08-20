# Mclash Codex Handoff

## Project

- Repository: `https://github.com/liuyi-htu/Mclash`
- Default and only permanent branch: `main`
- Clients built from this repository:
  - Root Android
  - Android VPN
  - Windows with both Mihomo and sing-box support

## Repository rules

- Keep only `main` after completing work. Use one temporary branch and one PR
  when a change must be published, then delete the temporary branch.
- Use `[skip ci]` in commits that only modify source, documentation, workflow
  defaults, or other non-build state.
- GitHub Actions must remain manual-only. A source change, push, PR, merge, or
  automatic version-default update must not trigger a build.
- Preserve the Android signing material already stored in the repository. Do
  not delete, replace, print, or expose signing secrets.
- Remove obsolete files only after confirming they are not required by any of
  the three clients or their build/release process.
- The repository owner has authorized the normal publish sequence for requested
  changes: commit, push, create one PR, merge into `main`, and delete the
  temporary branch. Do not create or retain additional branches.

## Build workflow

- Workflow: `.github/workflows/build-all.yml`
- It is started only with `workflow_dispatch`.
- The build target choices are `all`, `root`, `android`, and `windows`.
- `version` and `build_number` are prefilled with the latest successfully
  published values.
- If the requested build number is empty, equal to, or lower than the latest
  build for the selected version, advance it automatically.
- Publish a GitHub Release only when the `all` target succeeds for Root Android,
  Android, and Windows.
- Include the version and build number in every artifact filename.
- Publish one `.sha256` file beside every APK or Windows installer.
- After a successful Release, use `VERSION_SYNC_DEPLOY_KEY` to update the
  workflow's default version and build number on `main`.
- The automatic default-update commit must contain `[skip ci]` and must not
  start another workflow run.

## Release notes

- Never use GitHub-generated release notes or `--generate-notes`.
- Do not show `What's Changed`, pull-request lists, contributors, comparison
  links, or `Full Changelog`.
- Resolve and display the Mihomo core version used by the build automatically.
- The manual workflow input `release_notes` contains optional user-written
  Markdown.
- When `release_notes` is empty, the body contains only:

  ```text
  Mihomo 内核：`<version>`
  ```

- When `release_notes` is not empty, append it unchanged below the Mihomo line,
  separated by one blank line.

## Failure handling

- When the user reports a failed build, stop/cancel the obsolete run first.
- Read the failed job logs, fix the actual cause, validate the workflow locally,
  publish the fix through one PR, and rerun the requested build.
- Monitor the replacement run until it completes. Do not report success before
  all requested jobs pass and the expected Release assets are present.
- At handoff, verify the latest Release, workflow defaults, and that the remote
  has only the `main` branch.
