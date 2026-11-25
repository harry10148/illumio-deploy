#!/usr/bin/env bash
# 文件與腳本的一致性檢查。全部通過回傳 0；有任何問題則列出並回傳 1。
#   1. SOP 結構：docs/{pce,ven,cert,platform}/*.md 的 H1、適用版本、最後更新、§1–§7
#   2. 機密字串：啟用碼形式的長十六進位字串、私鑰
#   3. 相對連結與錨點：所有納入版控的 .md
#   4. Windows 腳本編碼：.ps1 為 UTF-8 BOM + CRLF；.bat 為 UTF-8 無 BOM + CRLF
#   5. Shell 腳本語法：bash -n
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)" || { echo "ERROR: must run inside a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1
fail=0
err() { echo "FAIL: $*"; fail=1; }

# --- 1. SOP 結構 ---
REQUIRED=(
  '^## 1\. 目的與適用情境$'
  '^## 2\. 前置條件$'
  '^## 3\. 操作步驟$'
  '^## 4\. 驗證$'
  '^## 5\. 失敗回滾 / 救援$'
  '^## 6\. 原廠文件參照$'
  '^## 7\. 與原廠差異（若有）$'
)
sop_count=0
for d in pce ven cert platform; do
  [[ -d "docs/$d" ]] || { err "missing directory: docs/$d"; continue; }
  for f in "docs/$d"/*.md; do
    [[ -e "$f" ]] || continue
    sop_count=$((sop_count + 1))
    head -1 "$f" | grep -qE '^# .+' || err "$f: 第一行必須是 H1 標題"
    grep -qE '^> \*\*適用版本\*\*：' "$f" || err "$f: 缺少「適用版本」"
    grep -qE '^> \*\*最後更新\*\*：[0-9]{4}-[0-9]{2}-[0-9]{2}$' "$f" || err "$f: 缺少「最後更新」或日期格式不是 YYYY-MM-DD"
    prev=0
    for pat in "${REQUIRED[@]}"; do
      line=$(grep -nE "$pat" "$f" | head -1 | cut -d: -f1)
      if [[ -z "$line" ]]; then err "$f: 缺少章節 $pat"
      elif (( line < prev )); then err "$f: 章節順序錯誤 $pat"
      else prev=$line; fi
    done
  done
done
(( sop_count > 0 )) || err "沒有找到任何 SOP，檢查可能沒有在看對的目錄"

# --- 2. 機密字串 ---
while IFS= read -r hit; do err "疑似啟用碼或私鑰: $hit"; done < <(
  git ls-files -z -- '*.md' '*.sh' '*.ps1' '*.bat' '*.yml' '*.yaml' |
  xargs -0 grep -nIE -- '(activation[-_ ]code[= :"]+[0-9a-f]{40,})|BEGIN ([A-Z]+ )?PRIVATE KEY' 2>/dev/null |
  grep -v '^scripts/check-docs.sh:' | cut -c1-80
)

# --- 3. 相對連結與錨點 ---
python3 - << 'PY' || fail=1
import re, subprocess, os, sys, unicodedata
files = subprocess.run(['git', 'ls-files', '-z', '--', '*.md'], capture_output=True, text=True).stdout.split('\0')
files = [f for f in files if f and not f.startswith('docs/guide/')]
def slug(h):
    h = re.sub(r'`', '', h.strip().lower())
    out = ''.join(c for c in h if c in '-_ ' or unicodedata.category(c)[0] in 'LN')
    return out.replace(' ', '-')
anchors = {}
for f in files:
    text = open(f, encoding='utf-8').read()
    text_nocode = re.sub(r'```.*?```', '', text, flags=re.S)
    a = set(slug(m) for m in re.findall(r'^#{1,6} +(.+?)\s*$', text_nocode, flags=re.M))
    a |= set(re.findall(r'<(?:span|a) id="([^"]+)"', text))
    anchors[f] = a
bad = 0
for f in files:
    text = re.sub(r'```.*?```', '', open(f, encoding='utf-8').read(), flags=re.S)
    for target in re.findall(r'\]\(([^)\s]+)\)', text):
        if re.match(r'[a-z]+:', target):
            continue
        path, _, frag = target.partition('#')
        dest = os.path.normpath(os.path.join(os.path.dirname(f), path)) if path else f
        if not os.path.exists(dest):
            print(f'FAIL: {f}: 連結目標不存在 {target}'); bad += 1; continue
        if frag and dest in anchors and frag not in anchors[dest]:
            print(f'FAIL: {f}: 錨點不存在 {target}'); bad += 1
sys.exit(1 if bad else 0)
PY

# --- 4. Windows 腳本編碼 ---
while IFS= read -r f; do
  bom=$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')
  crlf_missing=$(grep -c -v $'\r$' "$f" || true)
  case "$f" in
    *.ps1) [[ "$bom" == "efbbbf" ]] || err "$f: .ps1 必須是 UTF-8 with BOM (PowerShell 5.1 才能正確讀取中文)" ;;
    *.bat) [[ "$bom" != "efbbbf" ]] || err "$f: .bat 不可帶 BOM" ;;
  esac
  [[ "$crlf_missing" == "0" ]] || err "$f: 有 $crlf_missing 行不是 CRLF 換行"
done < <(git ls-files -- '*.ps1' '*.bat')

# --- 5. Shell 腳本語法 ---
while IFS= read -r f; do
  bash -n "$f" 2>/dev/null || err "$f: bash 語法錯誤"
done < <(git ls-files -- '*.sh')

if [[ $fail -eq 0 ]]; then echo "OK: $sop_count 份 SOP 結構正確，連結、編碼、語法與機密字串檢查通過"; fi
exit $fail
