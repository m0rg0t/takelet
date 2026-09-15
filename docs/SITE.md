# Project site

The Takelet landing page lives in `site/` and has two public destinations:

- GitHub Pages: <https://m0rg0t.github.io/takelet/>
- ChatGPT Sites: <https://takelet.antonlenev.chatgpt.site/>

Both use the same static HTML, CSS and optional clipboard script, with no package
installation, tracking, remote fonts or application backend. GitHub Pages remains
the canonical URL in the shared HTML.

## Preview and check

From the repository root:

```sh
python3 scripts/check-site.py
node --check site/site.js
python3 -m http.server 4173 --bind 127.0.0.1 --directory site
```

Open <http://127.0.0.1:4173/>. Stop the server with Ctrl-C when finished.
The static check verifies local links, anchors, image alt attributes and relative
asset paths; it does not replace browser, mobile or accessibility testing.

## Publish to GitHub Pages

Repository **Settings → Pages → Build and deployment → Source** must be
**GitHub Actions**. The `Project site` workflow validates pull requests and deploys
changes to `site/` on `main`. It also supports a manual run from the Actions tab.
Only `site/` is uploaded as the Pages artifact.

The deploy job uses the `github-pages` environment and the standard Pages/OIDC
permissions. See GitHub's [custom workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

Use relative URLs for assets so the `/takelet/` project prefix works. Update the
canonical and Open Graph URLs if the public address changes. To undo a content
change, revert its commit and let the same workflow deploy the previous content.

## Publish to ChatGPT Sites

`.openai/hosting.json` identifies the existing Site and selects `site/` as the
static directory. It contains no credentials. The Site is public by the owner's
request. Use the installed **Sites hosting** skill and connector to publish:

1. Validate the site and commit the reviewed source. Push `main` to GitHub.
2. Reuse the manifest's Site ID and obtain a short-lived source write credential.
3. Push the same commit to the returned Sites source repository and branch, using
   per-command authentication. Never save the token in a file or Git configuration.
4. Read the full commit SHA after the push succeeds. Package with the hosting
   skill's helper; only static assets and required hosting metadata are deployed.
5. Save the archive with that exact commit, deploy the saved version to the
   existing public Site, and wait for successful deployment.

Check existing versions first after an interrupted publication to avoid duplicate
work. Reuse the current audience; do not change sharing as a workaround for a
deployment error. Keep the native build and local recordings out of the archive.

### Keeping both copies current

When editing this site's code in Codex, publish both destinations before finishing
the task, as recorded in `AGENTS.md`. A GitHub push alone updates GitHub Pages;
the Sites connector requires its own publication step. Its available automatic
publish-on-push option is for private sites, so it is not used for this public copy.

## Content and images

The landing page distinguishes implemented features, experiments and the roadmap.
Keep those claims aligned with the README. The main action builds from source;
replace it with a download only after a signed, notarized release exists.

`assets/editor-dark.png` is a real Takelet window using generated media from
`takelet-media-check`. Refresh it through a native window screenshot when the UI
changes. Do not publish customer recordings, private projects or provider keys.
