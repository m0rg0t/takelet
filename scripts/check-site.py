#!/usr/bin/env python3
"""Check deployable assets and links without a browser or third-party packages."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys

root = Path(__file__).resolve().parent.parent / 'site'
problems = []


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path = path
        self.ids = set()
        self.references = []

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


pages = {}
for path in root.rglob('*.html'):
    page = Page(path)
    page.feed(path.read_text())
    pages[path] = page


def check_reference(source, reference):
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
for path in root.rglob('*'):
    if path.is_symlink():
        problems.append(f'{path.name}: symlinks are not deployable assets')
if not (root / 'index.html').is_file() or not (root / '.nojekyll').is_file():
    problems.append('Missing index.html or .nojekyll')
if problems:
    print('\n'.join(problems), file=sys.stderr)
    sys.exit(1)
print(f'Checked {len(pages)} HTML page(s): local assets, anchors, image text, and Pages paths pass.')
