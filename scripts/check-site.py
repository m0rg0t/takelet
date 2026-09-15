#!/usr/bin/env python3
"""Check deployable assets and links without a browser or third-party packages."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from urllib.robotparser import RobotFileParser

root = Path(__file__).resolve().parent.parent / 'site'
problems = []


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path = path
        self.ids = set()
        self.references = []
        self.meta = {}
        self.links = {}
        self.title = ''
        self.json_ld = []
        self.capture = None
        self.buffer = ''

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if 'id' in attrs:
            if attrs['id'] in self.ids:
                problems.append(f'{self.path.name}: duplicate id {attrs["id"]}')
            self.ids.add(attrs['id'])
        for name in ('href', 'src'):
            if attrs.get(name):
                self.references.append(attrs[name])
        if tag == 'img' and 'alt' not in attrs:
            problems.append(f'{self.path.name}: image has no alt attribute')
        if tag == 'meta':
            name = attrs.get('property') or attrs.get('name')
            if name:
                if name in self.meta:
                    problems.append(f'{self.path.name}: duplicate metadata {name}')
                self.meta[name] = attrs.get('content', '')
        if tag == 'link' and attrs.get('rel'):
            self.links[attrs['rel']] = attrs
        if tag == 'title' or (tag == 'script' and attrs.get('type') == 'application/ld+json'):
            self.capture, self.buffer = tag, ''

    def handle_data(self, data):
        if self.capture:
            self.buffer += data

    def handle_endtag(self, tag):
        if tag == self.capture:
            if tag == 'title':
                self.title = self.buffer.strip()
            else:
                self.json_ld.append(self.buffer)
            self.capture = None


pages = {}
for path in root.rglob('*.html'):
    page = Page(path)
    page.feed(path.read_text())
    pages[path] = page

home = pages.get(root / 'index.html')
canonical = home.links.get('canonical', {}).get('href', '') if home else ''


def check_reference(source, reference):
    if canonical and reference.startswith(canonical):
        reference = reference[len(canonical):] or 'index.html'
        if reference.startswith('#'):
            reference = 'index.html' + reference
        source = root / 'index.html'
    url = urlsplit(reference)
    if url.scheme or url.netloc:
        if url.scheme not in {'https', 'mailto'}:
            problems.append(f'{source.name}: unexpected external URL {reference}')
        return
    if url.path.startswith('/'):
        problems.append(f'{source.name}: root-relative URL breaks project Pages: {reference}')
        return
    target = (source.parent / unquote(url.path)).resolve() if url.path else source
    if not target.is_relative_to(root) or not target.is_file():
        problems.append(f'{source.name}: missing or out-of-site target {reference}')
    elif url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids:
        problems.append(f'{source.name}: missing anchor {reference}')


for path, page in pages.items():
    for reference in page.references:
        check_reference(path, reference)
for path in root.rglob('*.css'):
    for reference in re.findall(r'url\([\s\"\']*([^\s\)\"\']+)', path.read_text()):
        check_reference(path, reference)
for path in (root / 'llms.txt', root / 'index.md'):
    if not path.is_file():
        problems.append(f'Missing {path.name}')
        continue
    content = path.read_text()
    if not content.startswith('# Takelet'):
        problems.append(f'{path.name}: missing project heading')
    for reference in re.findall(r'\[[^\]]+\]\(([^\s)]+)\)', content):
        check_reference(path, reference)
        raw_prefix = 'https://raw.githubusercontent.com/m0rg0t/takelet/main/'
        if reference.startswith(raw_prefix):
            document = (root.parent / reference[len(raw_prefix):]).resolve()
            if not document.is_relative_to(root.parent) or not document.is_file():
                problems.append(f'{path.name}: missing repository document {reference}')

if home:
    meta = home.meta
    if urlsplit(canonical).scheme != 'https' or not canonical.endswith('/'):
        problems.append('Canonical URL must be an absolute HTTPS directory URL')
    if not 15 <= len(home.title) <= 70 or not 50 <= len(meta.get('description', '')) <= 170:
        problems.append('Missing or excessively long search title/description')
    for name in ('og:type', 'og:site_name', 'og:title', 'og:description', 'og:image:alt',
                 'og:image', 'og:image:type', 'og:image:width', 'og:image:height', 'og:url',
                 'twitter:card', 'twitter:title', 'twitter:description', 'twitter:image',
                 'twitter:image:alt'):
        if not meta.get(name):
            problems.append(f'Missing social metadata: {name}')
    if meta.get('og:url') != canonical:
        problems.append('Open Graph URL must match the canonical page')
    if meta.get('twitter:card') != 'summary_large_image':
        problems.append('Social preview must use a large image card')
    for suffix in ('title', 'description', 'image', 'image:alt'):
        if meta.get('twitter:' + suffix) != meta.get('og:' + suffix):
            problems.append(f'Open Graph and X {suffix} disagree')
    for relation, filename in (('alternate', 'index.md'), ('describedby', 'llms.txt'), ('sitemap', 'sitemap.xml')):
        if home.links.get(relation, {}).get('href') != './' + filename:
            problems.append(f'Missing discovery link for {filename}')
    robots = {value.strip().lower() for value in meta.get('robots', '').split(',')}
    if not {'index', 'follow', 'max-image-preview:large'} <= robots or {'noindex', 'nofollow', 'none'} & robots:
        problems.append('Page must permit indexing and large image previews')
    image_url = meta.get('og:image', '')
    if not canonical or not image_url.startswith(canonical):
        problems.append('Social image must have an absolute URL on the canonical site')
    else:
        check_reference(home.path, image_url)
        image_path = (root / image_url[len(canonical):]).resolve()
        if image_path.is_relative_to(root) and image_path.is_file():
            header = image_path.read_bytes()[:24]
            if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
                problems.append('Social image is not a PNG')
            else:
                width, height = struct.unpack('>II', header[16:24])
                if (str(width), str(height)) != (meta.get('og:image:width'), meta.get('og:image:height')):
                    problems.append('Social image dimensions do not match its metadata')
                if height == 0 or width < 600 or not 1.7 <= width / height <= 2.1:
                    problems.append('Social image must be a large landscape card')
            if meta.get('og:image:type') != 'image/png':
                problems.append('Social image MIME type must be image/png')
    try:
        if len(home.json_ld) != 1:
            raise ValueError('Expected one JSON-LD graph')
        data = json.loads(home.json_ld[0])
        if data.get('@context') != 'https://schema.org':
            raise ValueError('Unexpected structured-data context')
        entities = {item['@type']: item for item in data['@graph']}
        website, webpage, app = (entities[name] for name in ('WebSite', 'WebPage', 'SoftwareApplication'))
        if any(item['url'] != canonical for item in (website, webpage, app)):
            raise ValueError('Structured-data URLs disagree with canonical')
        if webpage['name'] != home.title or webpage['description'] != meta['description']:
            raise ValueError('Structured page title/description disagree with HTML')
        if app['image'] != image_url or webpage['primaryImageOfPage']['url'] != image_url:
            raise ValueError('Structured-data social images disagree with Open Graph')
        if app['downloadUrl'] not in home.references or app['softwareVersion'] not in app['downloadUrl']:
            raise ValueError('Structured download/version disagree with the visible release link')
        check_reference(home.path, app['screenshot'])
    except (ValueError, KeyError, TypeError) as error:
        problems.append(f'Invalid or inconsistent structured data: {error}')
    try:
        sitemap = ET.parse(root / 'sitemap.xml')
        locations = [node.text for node in sitemap.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc')]
        if locations != [canonical]:
            problems.append('Sitemap must list the canonical homepage once')
    except (OSError, ET.ParseError) as error:
        problems.append(f'Invalid sitemap: {error}')
    try:
        parser = RobotFileParser()
        parser.parse((root / 'robots.txt').read_text().splitlines())
        if not parser.can_fetch('*', canonical) or parser.site_maps() != [canonical + 'sitemap.xml']:
            problems.append('robots.txt must permit crawling and name the canonical sitemap')
    except OSError as error:
        problems.append(f'Missing robots.txt: {error}')
for path in root.rglob('*'):
    if path.is_symlink():
        problems.append(f'{path.name}: symlinks are not deployable assets')
if not (root / 'index.html').is_file() or not (root / '.nojekyll').is_file():
    problems.append('Missing index.html or .nojekyll')
if problems:
    print('\n'.join(problems), file=sys.stderr)
    sys.exit(1)
print(f'Checked {len(pages)} HTML page(s): links, assets, SEO metadata, social image, structured data, sitemap, and Markdown pass.')
