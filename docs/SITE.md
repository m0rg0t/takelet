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
The static check verifies local links, anchors, image alt attributes, relative
asset paths, SEO metadata, social-image dimensions, JSON-LD consistency, the
sitemap, and Markdown links. It does not replace browser, mobile or accessibility
testing.

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

`.openai/hosting.json` identifies the existing Site and selects `dist/` as the
static output directory. It contains no credentials. The Site is public by the owner's
request. Use the installed **Sites hosting** skill and connector to publish:

1. Validate the site and commit the reviewed source. Push `main` to GitHub.
2. Reuse the manifest's Site ID and obtain a short-lived source write credential.
3. Push the same commit to the returned Sites source repository and branch, using
   per-command authentication. Never save the token in a file or Git configuration.
4. Read the full commit SHA after the push succeeds. Run
   `python3 scripts/build-site.py` to copy the validated `site/` into the generated
   `dist/` directory, then package with the hosting skill's helper. Only static
   assets and required hosting metadata are deployed. Do not author files in `dist/`.
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
Keep those claims aligned with the README. The main action downloads the signed,
notarized Apple Silicon DMG from its versioned GitHub release URL. Update that
link only after verifying the new release asset is public and its checksum
matches. Keep source-build instructions and the developer-preview status visible.

`assets/editor-dark.png` is a real Takelet window using generated media from
`takelet-media-check`. Refresh it through a native window screenshot when the UI
changes. Do not publish customer recordings, private projects or provider keys.

## Search, sharing, and AI-readable documentation

The shared HTML contains a descriptive search title, description, canonical URL,
indexing directives, Open Graph and X large-card metadata, and Schema.org
`WebSite`, `WebPage`, and `SoftwareApplication` data. Keep release versions,
download URLs, requirements, and feature claims consistent with the visible page.
Do not invent ratings or reviews. The schema describes the app; it does not
guarantee eligibility for Google's software-app rich results.

- `site/og.png` is the branded social card. Both hosts reference its absolute
  GitHub Pages URL. Keep its dimensions and alt text in sync with the HTML.
- `site/sitemap.xml` lists the canonical homepage. Sections are anchors, not
  separate pages. Add new canonical HTML pages when the site grows. No synthetic
  `lastmod` date is emitted on routine builds.
- `site/robots.txt` allows crawling and points to the canonical sitemap. Robots
  rules apply only at an origin's `/robots.txt`: this file is effective at the
  ChatGPT Sites root, while GitHub serves it under `/takelet/robots.txt`, where
  crawlers do not use it as host policy. This project does not manage the GitHub
  account site's root robots file.
- `site/index.md` is a concise Markdown edition of the product page.
- `site/llms.txt` is a curated Markdown documentation index. HTML discovery links
  expose both files. Keep shipped, experimental, and planned capabilities distinct
  in all three editions. `llms.txt` is a proposed convention, not a guarantee of
  AI crawler support, inclusion, or ranking.

GitHub Pages remains canonical on both hosts to consolidate duplicate content.
If the primary address changes, update the HTML, JSON-LD, social-image URLs,
sitemap, robots sitemap pointer, and Markdown links together. The checker runs
in the Pages workflow before deployment. After publishing, confirm that both
hosts serve the HTML, image, sitemap, and text files publicly. Search engines
and social platforms decide when to crawl or refresh cached previews.

References: [Open Graph](https://ogp.me/),
[Google software-app structured data](https://developers.google.com/search/docs/appearance/structured-data/software-app),
[Google robots.txt location rules](https://developers.google.com/crawling/docs/robots-txt/create-robots-txt),
and the [llms.txt proposal](https://llmstxt.org/).
