# Project site

The Takelet landing page lives in `site/` and is published at
<https://m0rg0t.github.io/takelet/>. It is static HTML, CSS and a small optional
clipboard script, with no package installation, tracking, remote fonts or backend.

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

## Publish

Repository **Settings → Pages → Build and deployment → Source** must be
**GitHub Actions**. The `Project site` workflow validates pull requests and deploys
changes to `site/` on `main`. It also supports a manual run from the Actions tab.
Only `site/` is uploaded as the Pages artifact.

The deploy job uses the `github-pages` environment and the standard Pages/OIDC
permissions. See GitHub's [custom workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

Use relative URLs for assets so the `/takelet/` project prefix works. Update the
canonical and Open Graph URLs if the public address changes. To undo a content
change, revert its commit and let the same workflow deploy the previous content.

## Content and images

The landing page distinguishes implemented features, experiments and the roadmap.
Keep those claims aligned with the README. The main action builds from source;
replace it with a download only after a signed, notarized release exists.

`assets/editor-dark.png` is a real Takelet window using generated media from
`takelet-media-check`. Refresh it through a native window screenshot when the UI
changes. Do not publish customer recordings, private projects or provider keys.
