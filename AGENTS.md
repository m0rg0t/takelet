# Takelet project guidance

## Website publishing

The project website is authored once in `site/` and has two public destinations:

- GitHub Pages: https://m0rg0t.github.io/takelet/
- ChatGPT Sites: https://takelet.antonlenev.chatgpt.site/

After an authorized website change, validate and publish the same source to both
destinations as part of completing the task. GitHub Pages deploys changes pushed
to `main`. Follow `docs/SITE.md` and the installed Sites hosting skill for ChatGPT
Sites; GitHub's workflow does not deploy that copy. The owner requested public
hosting and continued updates to both copies.

Reuse the exact `project_id` in `.openai/hosting.json`. Never create another Site
for this project. Do not commit credentials, local recordings, analysis artifacts
or build caches. The deployment archive contains only `site/` and the required
hosting metadata, not the native application's sources.

Keep developer-preview claims aligned with the app. Screenshots must use
synthetic or explicitly shareable content. Do not imply a signed app download
exists until a signed, notarized release is available.
