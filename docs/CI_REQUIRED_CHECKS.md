# Required checks

GitHub is not configured from this repository. A pull request stays mergeable until the repository owner turns these checks on. The automation token used to inspect branch protection received HTTP 403, so this file is the setting list, not proof that the rule is already on.

## What to enable

On GitHub: **Settings → Rules → Rulesets** (or **Settings → Branches → Add branch protection rule**).

Protect `main`:

1. Require a pull request before merging.
2. Require status checks to pass before merging.
3. Require branches to be up to date before merging.
4. Do not allow bypasses for administrators if the goal is that a red check blocks every merge.
5. Add these checks after they have run on a pull request at least once. GitHub only offers a check name it has already seen.

| Check name | Workflow | What a red check means |
| --- | --- | --- |
| `Checks / Domain tests` | `.github/workflows/checks.yml` | Domain tests on Linux failed |
| `Checks / Project file and strings` | `.github/workflows/checks.yml` | Project file, string catalog, screenshot frames, or the generated Xcode project drifted |
| `Checks / SwiftLint` | `.github/workflows/checks.yml` | A new SwiftLint violation, outside `swiftlint-baseline.json` |
| `macOS / Build and test` | `.github/workflows/macos.yml` | Simulator build, unit tests, UI tests, Keychain tests, or coverage collection failed |
| `Sideload IPA / Unsigned device ipa` | `.github/workflows/sideload-ipa.yml` | The unsigned device build failed |

Do not mark **TestFlight** required. `.github/workflows/testflight.yml` does not run on pull requests. A manual run or a `v*` tag fails if an Apple secret is missing. A missing `GOOGLE_MAPS_API_KEY` warns and the archive continues.

## What the macOS check covers

- Unit tests on the iPhone simulator and again on the iPad simulator.
- UI tests on the iPhone simulator, including a test that saves a load.
- Code coverage for the iPhone unit-test run. The line-coverage table is appended to the job summary.
- The database-passphrase test and the Telegram token test. The job links `Tools/SimulatorHost.entitlements` (`keychain-access-groups`) into the simulator host's `__entitlements` section, as Xcode does for simulator builds, and keeps the ad-hoc signature free of entitlements. If either test is skipped, or the log says the Keychain refused the host, the job fails.

`Tools/SimulatorHost.entitlements` is only applied on that CI host. Device, Sideload, and App Store signing still use `TruckoRig/Resources/TruckoRig.entitlements` and do not gain a Keychain Sharing capability.

## SwiftLint

`swiftlint lint --strict` runs on the Ubuntu Checks job with SwiftLint 0.65.1. The rules are force cast, force try, force unwrap, line length (120 / 200), and TODO. Those rules run without SourceKit. Violations already in the tree are in `swiftlint-baseline.json`. A new one fails the check. Refresh the baseline only when an existing violation is removed or intentionally kept:

```bash
swiftlint lint --write-baseline swiftlint-baseline.json
```
