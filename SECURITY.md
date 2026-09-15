# Security and privacy

Takelet is a developer preview. Use test recordings while evaluating it.

The native recorder/editor has no application backend. A project contains its source media, edit metadata and cursor samples. Treat the entire `.takelet` package as sensitive if it contains a private screen recording. The optional command-line analyzer sends selected frames to the configured Codex account when explicitly invoked. See [AI analysis](docs/AI_ANALYSIS.md) for the current isolation boundaries.

If you discover a vulnerability, do not attach private recordings, keys, or authentication files to a public issue. Prefer GitHub's private vulnerability reporting for this repository once enabled. If that option is unavailable, open a minimal issue asking for a private contact without disclosing exploit details.

There is no response-time commitment at this early stage. Fixes target the current main branch; older developer builds are not maintained separately.
