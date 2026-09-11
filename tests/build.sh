#!/usr/bin/env bash
# Build a deck and run the conformance checks over it.
#
#     tests/build.sh                 # the preview, showcase.qmd
#     tests/build.sh stress.qmd
#
# Uses quarto when it is installed. Without quarto it drives pandoc and
# pdflatex directly, which exercises the same filter, theme and components --
# enough to check the output, though quarto is the supported path.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="${1:-$root/showcase.qmd}"
ext="$root/_extensions/deegan/dublin"
out="$root/tests/build"

mkdir -p "$out"

if command -v quarto >/dev/null 2>&1; then
  quarto render "$src" --to dublin-beamer --output-dir "$out"
  pdf="$out/$(basename "${src%.qmd}").pdf"
  python3 "$root/tests/check.py" "$pdf"
  exit $?
fi

echo "quarto not found; building through pandoc"

cp "$ext"/*.tex "$ext"/*.lua "$out/"
for dir in figures examples img; do
  [ -d "$root/$dir" ] && cp -r "$root/$dir" "$out/"
done
for asset in "$root"/*.png; do
  [ -e "$asset" ] && cp "$asset" "$out/"
done

# Front matter -> pandoc variables. The filter reads the cover keys itself.
python3 - "$src" "$out" <<'PY'
import re, sys, pathlib
src, out = sys.argv[1], pathlib.Path(sys.argv[2])
text = pathlib.Path(src).read_text()
_, front, body = text.split('---', 2)
out.joinpath('body.md').write_text(body.lstrip('\n'))

meta = {}
for line in front.splitlines():
    m = re.match(r'^([a-z-]+):\s*(.+)$', line.strip())
    if m:
        meta[m.group(1)] = m.group(2).strip().strip('"')
# Shell-safe: only the key is rewritten, values are single-quoted as-is,
# so a hyphen inside a subtitle survives.
def sh(v):
    return "'" + v.replace("'", "'\\''") + "'"
out.joinpath('meta.sh').write_text('\n'.join(
    f'meta_{k.replace("-", "_")}={sh(v)}' for k, v in meta.items()) + '\n')

# Cover keys reach the preamble through the filter's Meta handler, which
# writes them into header-includes. Quarto passes that through; bare pandoc
# drops it whenever -H is also given, so on this fallback path the same
# settings are written to a file and included directly.
MACRO = {'cover-photo': 'coverphoto', 'cover-scrim': 'coverscrim',
         'cover-badge': 'coverbadge', 'cover-logo': 'coverlogo',
         'qr-code': 'thanksqr', 'qr': 'thanksqr',
         'short-title': 'shorttitle'}
lines = [f'\\{MACRO[k]}{{{v}}}' for k, v in meta.items() if k in MACRO]
out.joinpath('cover.tex').write_text('\n'.join(lines) + '\n')
PY

cd "$out"
# shellcheck disable=SC1091
source ./meta.sh

args=(--to beamer --standalone --slide-level=2
      --lua-filter=dublin-blocks.lua
      -H dublin-theme.tex -H dublin-components.tex -H cover.tex
      -V aspectratio=169 -V classoption=t -V fontsize=11pt
      -V theme=default -V navigation=empty
      -V "title=${meta_title:-Untitled}"
      -V "author=${meta_author:-}"
      -V "institute=${meta_institute:-}"
      -V "date=${meta_date:-}")
[ -n "${meta_subtitle:-}" ] && args+=(-V "subtitle=${meta_subtitle}")
[ -f "$root/refs.bib" ] && cp "$root/refs.bib" . && args+=(--citeproc --bibliography=refs.bib)

pandoc body.md -o out.tex "${args[@]}"
pdflatex -interaction=nonstopmode out.tex >/dev/null 2>&1 || true
pdflatex -interaction=nonstopmode out.tex >/dev/null 2>&1 || true

python3 "$root/tests/check.py" out.pdf out.tex out.log
