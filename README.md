# Jaglosky

**The maintenance agent for mobile app fleets.** Jaglosky watches the App Store and Google Play requirements, tells you
which of your apps are at risk, fixes what it can as tested pull requests, and gives a go / no-go before every release.

Everything runs in your own CI with your own keys. Your code never leaves your GitHub; the agent can only open pull
requests.

This repository is the distribution: the reusable workflows and GitHub Actions your repositories call (`@v1`) and
the bundled command-line tool.

## What it does

- **Radar** — scans each app (React Native / Expo, Flutter, native Android and iOS) against the current store rules and
  known vulnerabilities, twice a week. One Slack digest and a plain-English PDF per fleet and per app.
- **Fixes** — for findings it can fix (target SDK, vulnerable packages, CI Xcode version, an Expo SDK upgrade one
  version at a time) an agent opens a pull request. The change is built and started on an emulator; the pull request
  carries screenshots and a recording of the launch. A person reviews and merges.
- **Release check** — release build, emulator and simulator smoke tests, store rules, store guideline checks on the
  built binaries → one verdict: go, go with warnings, or no-go.

## Requirements

- GitHub Actions (Linux runners; a macOS runner only for iOS builds).
- Optional: an Anthropic API key (`ANTHROPIC_API_KEY`) for the fix pull requests, a Slack incoming webhook
  (`SLACK_WEBHOOK_URL`) for the digests.

## Set up

Copy `templates/github/jaglosky.yml` and `templates/github/jaglosky-release-check.yml` from this repository into your
app repository's `.github/workflows/`. They are short: triggers, permissions and your secrets — the jobs themselves
live here and are called at `@v1`. Then:

1. Repository → Settings → Actions → General → Workflow permissions: **Read and write**, and allow GitHub Actions to
   create pull requests.
2. Add the secrets you want to use (Settings → Secrets and variables → Actions): `SLACK_WEBHOOK_URL` for the digests,
   `ANTHROPIC_API_KEY` for the fix pull requests. The radar works without either.
3. Run the workflow once by hand: Actions → Jaglosky → Run workflow → mode `scan`.

From then on the radar runs every Monday and Thursday.

## Versions

Your workflow files call `jaglosky/jaglosky/.github/workflows/<name>.yml@v1`. `v1` moves with every compatible
release, so fixes reach you without changing those files; pin a full tag (for example `@v1.1.0`) if you prefer to
upgrade deliberately.

## License

Proprietary — see `LICENSE.md`. The command-line tool is distributed as a bundle; the scripts in `.github/actions/`
are readable so that you can see exactly what runs in your CI.
