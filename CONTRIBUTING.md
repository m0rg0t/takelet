# Contributing to Takelet

Takelet is an early native macOS project. Small, focused pull requests are welcome.

1. Read the [roadmap](docs/ROADMAP.md) and [architecture](docs/ARCHITECTURE.md).
2. Open an issue before introducing a new service, dependency, project-file format or large UI change.
3. Build and test on Apple Silicon with macOS 15 or later and a Swift 6 toolchain:

   ```sh
   sh scripts/swift-check.sh test
   sh scripts/build-app.sh
   ```

4. For media changes, run the synthetic media check described in [testing](docs/TESTING.md). Compare preview, exported frames and audio timing.
5. Explain the visible change and how you tested it in the pull request. Include a screenshot for UI changes using synthetic or explicitly shareable content.

## Engineering conventions

- Keep the original recording intact. Store edits in the project document.
- Use source timestamps for cuts, zooms and cursor samples. Use the shared time mapping when rendering output.
- Keep preview and export on the same composition path.
- Validate model output in application code. Suggestions never execute commands or silently alter recordings.
- Keep network-dependent and account-dependent checks opt-in. CI must not require Codex login, API keys, screen recording permission, or access to someone's desktop.
- Make Mac UI changes accessible, keyboard-friendly and undoable.

Do not commit recordings, personal frames, provider logs, credentials or local notes. The publication check catches common mistakes; review your staged diff as well.

By contributing, you agree that your contribution is available under the project's [MIT license](LICENSE). Only contribute work you have the right to share.
