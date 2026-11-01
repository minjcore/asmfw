#!/usr/bin/env python3
"""Check the generated module documentation against the sources.

    python3 docs/verify.py

Walks every generated file under docs/modules/ and docs/vi/modules/ and re-derives
every claim it makes. Line numbers are the one kind of documentation that rots
without any sign of it -- a label moves, the link still resolves, the row still
looks right, and nothing complains. This complains.

Four things are checked per module file:

    1. the source file the doc points at exists
    2. it has exactly as many lines as the doc says (counted as `wc -l` counts)
    3. every symbol in the entry-point table really is defined on the line given
    4. the entry-point count in the header matches the number of table rows

Language-agnostic: it reads the structure, not the labels, so the English and
Vietnamese trees are checked the same way.

Exit status is 0 if the documentation matches the code, 1 if it does not.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TREES = ('docs/modules', 'docs/vi/modules')

# [`src/util.asm`](../../../src/util.asm) — 201 lines, 12 entry points.
HEAD = re.compile(r'^\[`([^`]+)`\]\(([^)]+)\)\s+—\s+(\d+)\s+[^,]+,\s+(\d+)\s')
# | `con_putc` | [13](../../../src/util.asm#L13) | ... |
ROW = re.compile(r'^\| `([a-z_][a-z0-9_]*)` \| \[(\d+)\]\(([^)#]+)#L(\d+)\)')


def lines_of(path):
    return open(path).read().count('\n')


def find(path, sym):
    for i, l in enumerate(open(path), 1):
        if l.startswith(sym + ':'):
            return i
    return None


def check_file(doc, problems):
    """Returns the number of claims checked in one module doc."""
    rel = os.path.relpath(doc, ROOT)
    here = os.path.dirname(doc)
    n = 0
    header = None
    rows = 0

    for lineno, line in enumerate(open(doc), 1):
        m = HEAD.match(line)
        if m and header is None:
            header = (lineno, m.group(1), m.group(2), int(m.group(3)), int(m.group(4)))
            n += 1
            claimed_path, link, nlines = m.group(1), m.group(2), int(m.group(3))
            target = os.path.normpath(os.path.join(here, link))
            if not os.path.exists(target):
                problems.append('%s:%d  %s does not exist' % (rel, lineno, link))
            else:
                if os.path.relpath(target, ROOT) != claimed_path:
                    problems.append('%s:%d  header names %s but links to %s'
                                    % (rel, lineno, claimed_path,
                                       os.path.relpath(target, ROOT)))
                actual = lines_of(target)
                if actual != nlines:
                    problems.append('%s:%d  %s: documented as %d lines, is %d'
                                    % (rel, lineno, claimed_path, nlines, actual))
            continue

        m = ROW.match(line)
        if m:
            sym, shown, link, anchor = m.group(1), int(m.group(2)), m.group(3), int(m.group(4))
            rows += 1
            n += 1
            if shown != anchor:
                problems.append('%s:%d  %s: text says line %d, link says %d'
                                % (rel, lineno, sym, shown, anchor))
                continue
            target = os.path.normpath(os.path.join(here, link))
            if not os.path.exists(target):
                problems.append('%s:%d  %s: %s does not exist' % (rel, lineno, sym, link))
                continue
            src = open(target).read().split('\n')
            if not (1 <= shown <= len(src)) or not src[shown - 1].startswith(sym + ':'):
                now = find(target, sym)
                problems.append('%s:%d  %s: documented at %s:%d, %s'
                                % (rel, lineno, sym, os.path.relpath(target, ROOT), shown,
                                   'now at line %d' % now if now else 'no longer defined there'))

    if header is None:
        problems.append('%s: no header line -- regenerate' % rel)
    else:
        n += 1
        if header[4] != rows:
            problems.append('%s:%d  header claims %d entry points, table has %d rows'
                            % (rel, header[0], header[4], rows))
    return n


def main():
    problems = []
    checked = 0
    files = 0

    for tree in TREES:
        base = os.path.join(ROOT, tree)
        if not os.path.isdir(base):
            problems.append('%s: missing -- run docs/generate.py' % tree)
            continue
        for dirpath, _, names in os.walk(base):
            for name in sorted(names):
                if not name.endswith('.md') or name == 'README.md':
                    continue
                files += 1
                checked += check_file(os.path.join(dirpath, name), problems)

    if problems:
        print('documentation is stale: %d problem(s) in %d claims across %d files\n'
              % (len(problems), checked, files))
        for x in problems:
            print('  ' + x)
        print('\nRun docs/generate.py, or fix them by hand.')
        return 1

    print('OK  %d claims checked across %d files, all match the sources' % (checked, files))
    return 0


if __name__ == '__main__':
    sys.exit(main())
