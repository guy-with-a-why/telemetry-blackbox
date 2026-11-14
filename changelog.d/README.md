# Changelog entries

I don't write the changelog by hand. release-please builds
[CHANGELOG.md](../CHANGELOG.md) from the Conventional Commits on `main`, so the
squashed pull request title is the entry.

| Commit type | Section | Version bump before 1.0 |
|---|---|---|
| `feat` | Features | minor |
| `fix` | Bug Fixes | patch |
| `feat!` or a `BREAKING CHANGE:` footer | Features, flagged breaking | minor |
| `perf`, `revert` | Performance Improvements, Reverts | patch |
| anything else | left out | none |

## Writing a good entry

- Write the title for someone reading the changelog, not the diff.
- Say what changed for a user, for example `feat(gateway): resync after a bad CRC`.
- Put upgrade steps for a breaking change in the `BREAKING CHANGE:` footer.
- Use a `Release-As: x.y.z` footer only to force a version.

## Fixing an entry

Edit the release pull request before it merges. Never edit a released section
of `CHANGELOG.md` or move a tag.
