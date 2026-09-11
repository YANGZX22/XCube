#!/usr/bin/env python3
"""Validate every inline tool JSON schema in the ArkTS sources.

The schemas live in template literals and are handed to JSON.parse at runtime,
so a malformed one compiles cleanly and then kills the app on startup
(registerBuiltinTools runs from ChatPage.aboutToAppear). hvigor cannot catch
this, so check it here instead.

The important subtlety: inside a template literal the JS engine processes
escapes *before* JSON.parse sees the text, so a `\\"` in the source becomes a
bare `"` and breaks the JSON. This script reproduces that unescaping before
parsing, which is exactly what the runtime does.

Usage: python3 tools/validate-tool-schemas.py
Exits non-zero and prints the offending file/line when a schema is invalid.
"""

import json
import pathlib
import re
import sys

ETS_ROOT = pathlib.Path(__file__).resolve().parent.parent / 'entry' / 'src' / 'main' / 'ets'

# `const <name>: string = ` + backtick-delimited body. Template literals here never
# contain a nested backtick, so a non-greedy match to the next backtick is exact.
SCHEMA_PATTERN = re.compile(
    r'(?:const|let)\s+\w*[Ss]chema\w*\s*:\s*string\s*=\s*`(.*?)`',
    re.DOTALL,
)

# Escape sequences a JS template literal resolves before the string reaches JSON.parse.
TEMPLATE_ESCAPES = {
    '\\': '\\', '"': '"', "'": "'", '`': '`', '$': '$',
    'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f', 'v': '\v', '0': '\0',
}


# `${...}` interpolations cannot be evaluated statically. Substitute a placeholder of
# the right JSON type so the surrounding structure still gets validated: a stringified
# expression stands in as a string, anything else as a number (the existing schemas
# interpolate numeric limits).
INTERPOLATION_PATTERN = re.compile(r'\$\{([^{}]*)\}')


def substitute_interpolations(raw: str) -> str:
    def replace(match: 're.Match[str]') -> str:
        expression = match.group(1)
        return '"placeholder"' if 'JSON.stringify' in expression else '0'

    return INTERPOLATION_PATTERN.sub(replace, raw)


def resolve_template_escapes(raw: str) -> str:
    out = []
    index = 0
    while index < len(raw):
        char = raw[index]
        if char == '\\' and index + 1 < len(raw):
            nxt = raw[index + 1]
            if nxt in TEMPLATE_ESCAPES:
                out.append(TEMPLATE_ESCAPES[nxt])
                index += 2
                continue
        out.append(char)
        index += 1
    return ''.join(out)


def main() -> int:
    failures = []
    checked = 0
    for path in sorted(ETS_ROOT.rglob('*.ets')):
        source = path.read_text()
        for match in SCHEMA_PATTERN.finditer(source):
            checked += 1
            line = source.count('\n', 0, match.start()) + 1
            resolved = resolve_template_escapes(substitute_interpolations(match.group(1)))
            try:
                parsed = json.loads(resolved)
            except json.JSONDecodeError as error:
                failures.append(
                    f'{path.relative_to(ETS_ROOT.parent.parent.parent.parent)}:{line}: '
                    f'{error.msg} at position {error.pos}\n'
                    f'    near: {resolved[max(0, error.pos - 40):error.pos + 40]!r}'
                )
                continue
            if not isinstance(parsed, dict):
                failures.append(
                    f'{path.relative_to(ETS_ROOT.parent.parent.parent.parent)}:{line}: '
                    'schema is not a JSON object'
                )

    if failures:
        print(f'Invalid tool schemas ({len(failures)} of {checked} checked):\n', file=sys.stderr)
        for failure in failures:
            print(f'  {failure}', file=sys.stderr)
        return 1

    print(f'All {checked} inline tool schemas parse as JSON.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
