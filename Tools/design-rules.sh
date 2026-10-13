#!/bin/bash
# 見た目の決まりを守っているかを確かめる。決まりの中身は Sources/Design.swift の先頭にある。
# 寸法・字の大きさ・角の数字を書いてよいのは Design.swift だけ。ほかのファイルで見つけたら落とす。
# AppKit で組んでいる設定の窓は macOS の見た目に従うので対象外
set -euo pipefail

cd "$(dirname "$0")/.."

FILES=$(ls Sources/*.swift | grep -v -e '/Design.swift$' -e '/SettingsWindow.swift$')
FAILED=0

rule() {
  local pattern="$1" reason="$2"
  # shellcheck disable=SC2086
  if grep -nE -- "$pattern" $FILES; then
    echo "NG: ${reason}" >&2
    FAILED=1
  fi
}

rule '\.font\(\.system\(size:' "字の大きさは Design の値を使う"
rule 'cornerRadius: *[0-9]' "角は Design.cornerRadius を使う"
rule '\.padding\((\.[a-z]+, *)?[0-9]' "余白は Design の値を使う"
rule '\.frame\((min|max)?([Ww]idth|[Hh]eight): *[0-9]' "行や枠の寸法は Design の値を使う"
rule 'RoundedRectangle\(' "枠は Card を使う"

if [ "$FAILED" = 1 ]; then exit 1; fi
echo "design-rules: ok"
