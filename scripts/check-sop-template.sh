#!/usr/bin/env bash
# Validate every docs/{pce,ven,cert,platform}/*.md has the required 7 sections.
# Exit 0 if all pass; non-zero with file:section list on failure.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)" || { echo "ERROR: must run inside a git repo" >&2; exit 1; }
fail=0
REQUIRED=(
  '^## 1\. 目的與適用情境$'
  '^## 2\. 前置條件$'
  '^## 3\. 操作步驟$'
  '^## 4\. 驗證$'
  '^## 5\. 失敗回滾 / 救援$'
  '^## 6\. 原廠文件參照$'
  '^## 7\. 與原廠差異（若有）$'
)
while IFS= read -r -d '' f; do
  for pat in "${REQUIRED[@]}"; do
    if ! grep -qE "$pat" "$f"; then
      echo "MISSING: $f -- $pat"
      fail=1
    fi
  done
done < <(find "$ROOT/docs/pce" "$ROOT/docs/ven" "$ROOT/docs/cert" "$ROOT/docs/platform" \
            -maxdepth 1 -name '*.md' -print0 2>/dev/null)
[[ $fail -eq 0 ]] && echo "OK: all SOPs have §1–§7"
exit $fail
