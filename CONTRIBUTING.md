## Logging & destructive helpers — rules for contributors 🚨

This project treats logging and destructive developer helpers as security-sensitive. Please follow these guidelines when changing code.

1) No raw printing in app source (high priority)
   - Do not use `print(...)`, `debugPrint(...)`, `NSLog(...)`, or `printf(...)` in app production sources.
   - Use the `AppLog` helpers instead: `AppLog.debugPublic`, `AppLog.debugPrivate`, `AppLog.info`, `AppLog.warning`, `AppLog.error`.
   - Why: raw printing can accidentally expose filenames, asset IDs, key material, or other user data in system diagnostics.

2) When to use debugPublic vs debugPrivate
   - `debugPrivate(...)` — for any message that contains user-identifying information such as filenames, asset IDs, paths, or secret-ish values.
   - `debugPublic(...)` — for developer-friendly messages that do not contain any user data and are safe to include in logs.
   - `info`/`warning`/`error` — use for non-sensitive runtime events and failures; prefer `error` for recoverable failures and `warning` for unexpected states.

3) Test code and _only_ test targets
   - Test targets (folders containing `Tests`, `UITests`, etc.) are allowed to print to stdout for debugging, but avoid leaking private sample data in automated runs.
   - CI runs scan the app source (not tests) for raw prints.

4) Destructive functions (e.g. `nukeAllData()`)
   - Dangerous destructive methods must remain inside `#if DEBUG` blocks and must never be available in Release builds.
   - Programmatic triggers (e.g., `--reset-state`) that call destructive helpers must require an explicit environment flag `ALLOW_DESTRUCTIVE_RESET=1` to run. This protects accidental test or CI runs from deleting data.

5) CI enforcement
   - The repo includes `scripts/check-no-prints.sh` which runs in CI and fails if un-gated `print`, `debugPrint`, `NSLog`, `printf` or unconditional `nukeAllData(` occurrences are present in non-test source.
   - A SwiftLint job is configured to check for raw prints and will fail PRs that introduce them.

6) Need an exception?
   - VERY rarely you might need a raw print. Add a comment `// ALLOWED_PRINT` on the same line and open a small PR note explaining why; the check script will whitelist that single occurrence after review.

7) Developer testing & running checks locally
   - Run the check script locally from the repository root:

     ```bash
     bash ./scripts/check-no-prints.sh
     ```

   - Run SwiftLint locally (macOS):

     ```bash
     brew install swiftlint
     swiftlint --config .swiftlint.yml

7) Install repository git hooks locally

- Use the provided installer script to set up the pre-commit hook that runs the checks locally:

   ```bash
   bash ./scripts/install-git-hooks.sh
   ```

   This copies `scripts/pre-commit.sh` to `.githooks/pre-commit` and sets `git config core.hooksPath .githooks` for the repo.

     ```

Thanks — following these rules helps keep user data private and prevents accidental destructive operations escaping developer environments. ✅
