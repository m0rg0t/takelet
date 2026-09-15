# Experimental AI analysis

`takelet-analyze` is a feasibility prototype, separate from the editor UI. It prepares evidence locally, requests structured observations through Codex, and validates candidate cuts. It never modifies the movie or applies project edits.

## Requirements and authentication

- macOS 15+ and the compiled Swift package.
- A local Codex CLI. **0.153.4** is the exercised version; verify protocol/capability changes before relying on others.
- An existing Codex-managed **ChatGPT login** for inference. If signed out, run `codex login` yourself.
- Python 3 for the optional HTML report.

Codex's app-server supports embedding its client protocol in an application. ChatGPT authentication uses the account's Codex allowance; API-key authentication has separate billing. This does not provide a universal API key for a ChatGPT subscription. See the official [app-server documentation](https://developers.openai.com/codex/app-server) and [authentication documentation](https://developers.openai.com/codex/auth).

Takelet does not copy credentials into projects or edit persistent Codex configuration. There is no automatic paid API fallback. Fresh login UI, account switching, general OpenAI-compatible providers and ElevenLabs are not implemented yet.

## Commands

```sh
sh scripts/swift-check.sh build
TAKELET_ANALYZER="${TMPDIR:-/private/tmp}/takelet-swift/build/debug/takelet-analyze"
"$TAKELET_ANALYZER" prepare /path/to/demo.mov artifacts/my-demo
"$TAKELET_ANALYZER" probe artifacts/my-account-check

# Sends selected frames to the signed-in Codex account.
"$TAKELET_ANALYZER" analyze artifacts/my-demo/manifest.json artifacts/my-result
python3 scripts/report.py artifacts/my-demo/manifest.json artifacts/my-result artifacts/my-report.html
```

Use fresh output directories. `prepare` is local. `probe` checks account type, models and shared limits without inference; its report omits identity and credentials. `analyze` is the network-dependent step and consumes shared account capacity.

`TAKELET_CODEX_BINARY` selects the executable. `TAKELET_CODEX_MODEL` deliberately overrides the model; otherwise the prototype selects the catalog's default image-capable model and default reasoning effort.

## Evidence and validation

Preparation samples at half-second intervals, stores actual decoded timestamps, computes coarse pixel changes, and selects at most 16 JPEGs per request. The image batch is capped at 12 MB. Source duration is bounded to roughly ten minutes; measurements use short clips.

The model receives selected images, timestamps, candidate/protected intervals and a task prompt. Application code validates source bounds, evidence IDs, cut overlaps and protected intervals. Invalid suggestions remain in `validated.json` with reasons. Eligible suggestions still need human review.

Artifacts include `analysis.json`, `validated.json`, `request.json`, `metrics.json` and a redacted connection snapshot. These can contain private screen content or descriptions; keep them local unless deliberately sharing them.

Static pixels are not proof that an interval is expendable. Small UI changes, text being read or brief motion can be missed. When a source has audio, the prototype protects the entire recording because speech/activity detection is not implemented. An inserted-hold experiment with an annotated protected ending is protocol evidence, not an accuracy benchmark.

## Cancellation

```sh
"$TAKELET_ANALYZER" analyze artifacts/my-demo/manifest.json artifacts/cancel-check --cancel-after 1
```

During inference, Ctrl-C or the optional delay requests `turn/interrupt`. A 180-second deadline also requests interruption; failure to acknowledge within 15 seconds closes the helper. Startup requests have separate deadlines, and startup cancellation is not immediate. Cancellation arriving after completion can legitimately return a completed result.

## Isolation boundaries

Each run creates ephemeral sessions with process-local overrides disabling shell, browser, apps, plugins, hooks, personal skill discovery and delegation. Configured MCP servers are disabled for the session, and the reported tool inventory is checked before inference. Unexpected permission/tool requests fail closed. Temporary runtime SQLite data is removed on orderly shutdown. Codex continues to manage normal account state and account-level activity.

**Codex 0.153.4 does not expose the restricted read-roots fields shown in newer documentation.** Its read-only sandbox is not OS-enforced confinement to the frame folder. The prototype validates local-image paths and suppresses tools, but stronger read isolation, crash cleanup and complete effective-tool auditing remain distribution work.

Keep app-server integration optional until protocol support and isolation are suitable for distribution. Exhausted limits should pause a job or require an explicit switch to another configured provider.
