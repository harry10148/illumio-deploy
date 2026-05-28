# Illumio SOP Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate 21 hand-written Illumio SOP `.txt` files from gitignored `tmp/` into version-controlled `docs/{pce,ven,cert,platform}/*.md` using a unified template, verify each against NotebookLM "Illumio" notebook (and `docs.illumio.com` fallback), and append "vendor reference / delta" blocks.

**Architecture:** Single PR, 4 commits matching the 4 spec stages (skeleton → migrate → verify → finalize). Migration preserves original commands verbatim under §3 of each `.md`. Verification uses `notebooklm ask -n 8c325126-bc83-4c86-8c6e-8759a242928e` with `WebFetch`/`WebSearch` fallback for `docs.illumio.com`. Original `.txt` files are deleted in stage 4 — their v0 commands survive verbatim in the new `.md` §3 fenced blocks.

**Tech Stack:** Bash + `notebooklm` CLI (v0.3.4) + WebFetch/WebSearch. No build / no compiled code. Validation via a small `scripts/check-sop-template.sh` shell helper.

**Spec:** `docs/superpowers/specs/2026-05-29-illumio-sop-integration-design.md`

---

## Pre-flight Checks (Do Once)

Run these before starting Task 1.

- [ ] **PF-1: Verify NotebookLM auth**

```bash
notebooklm status
notebooklm auth check
```

Expected: "Authenticated as: <email>"; if not authenticated, run `notebooklm login`.

- [ ] **PF-2: Verify "Illumio" notebook ID resolves**

```bash
notebooklm source list -n 8c325126-bc83-4c86-8c6e-8759a242928e 2>&1 | head -3
```

Expected: header `Sources in 8c325126-...` with no error.

- [ ] **PF-3: Confirm `tmp/` is gitignored and contains 21 .txt + `guide/` with 2 docx**

```bash
git check-ignore -v tmp/illumio_backup_v4.txt
ls tmp/*.txt | wc -l               # expect 21
ls "tmp/guide/" | wc -l             # expect 2
```

- [ ] **PF-4: Confirm clean working tree on `main`**

```bash
git status --short
git branch --show-current           # expect main
```

If dirty, ask before starting.

---

## Task 1: Stage 1 — Skeleton

**Files:**
- Create: `docs/{pce,ven,cert,platform,guide}/.gitkeep`
- Create: `docs/SOP-TEMPLATE.md`
- Create: `docs/README.md` (stub; full index in Task 4)
- Create: `scripts/check-sop-template.sh`
- Modify: `.gitignore` (append `docs/guide/*.docx`)
- Move: `tmp/guide/*.docx` → `docs/guide/*.docx` (plain `mv`, not `git mv`)

- [ ] **Step 1.1: Create empty category directories with `.gitkeep`**

```bash
cd /home/harry/rd/illumio-deploy
mkdir -p docs/{pce,ven,cert,platform,guide}
touch docs/{pce,ven,cert,platform,guide}/.gitkeep
```

- [ ] **Step 1.2: Write `docs/SOP-TEMPLATE.md`**

Create file with EXACT content (this is the canonical template referenced by every SOP):

````markdown
# SOP Template (繁中)

> 所有 `docs/{pce,ven,cert,platform}/*.md` 必須遵守本模板。新增 SOP 時複製本檔，
> 改名後填入內容。**§1–§7 段標題與順序不得更動**。

---

# <SOP 標題（繁中）>

> **適用版本**：Illumio PCE 25.x / VEN 25.x（依驗證結果填）
> **更新日期**：YYYY-MM-DD
> **原始檔**：`tmp/<原 .txt 檔名>`（v0 內容已逐字併入下方 §3；tmp/ 自始未入 git）

## 1. 目的與適用情境

一句話說明 SOP 解決什麼問題、何時用。

## 2. 前置條件

- 權限：…
- 工具：…
- 網路 / 防火牆：…

## 3. 操作步驟

原 SOP 指令逐字保留，加上中文註解；命令一律放 fenced code block：

```bash
# 範例
sudo illumio-pce-ctl status
```

## 4. 驗證

- 觀察點 1：…
- 觀察點 2：…

## 5. 失敗回滾 / 救援

如步驟 N 失敗該做什麼。

## 6. 原廠文件參照

- [NotebookLM] `Illumio_PCE操作手冊` §x.y
- [NotebookLM] `Admin_25_4.pdf` — Backup chapter
- [Web] https://docs.illumio.com/…（NotebookLM 缺漏時的補充來源）

## 7. 與原廠差異（若有）

- 步驟 3：本 SOP 用 `…`，原廠 25.4 為 `…`，因 <現場限制>
- 步驟 N：**原廠文件未涵蓋**（NotebookLM + 公開 docs 皆查無）

---

## 模板強制規則（給新增 SOP 的人）

1. §1–§7 必須齊全；無內容寫「— 無 —」。
2. §3 指令逐字保留**原 SOP** 內容，不擅自改動（差異走 §7 註記）。
3. §6 來源標籤：`[NotebookLM]` / `[Web]` / `[現場]` 三選一，混用標明。
4. §7 若實際無差異，仍須保留段標並寫「驗證結果與原廠一致」。
````

- [ ] **Step 1.3: Write stub `docs/README.md`**

```markdown
# Illumio 維運 SOP

> 完整索引將在 Stage 4 完成。模板與規則見 [SOP-TEMPLATE.md](./SOP-TEMPLATE.md)。

- `pce/` — PCE 伺服器端 SOP
- `ven/` — VEN 端點 SOP
- `cert/` — 憑證與 SSL
- `platform/` — K8s / FlowLink / Linux 平台
- `guide/` — 原廠中文手冊（本機快取，不入 git）
```

- [ ] **Step 1.4: Append `docs/guide/*.docx` to `.gitignore`**

Append these lines to `.gitignore` (after the existing `*.zip` rule near line 34):

```
# Illumio vendor manuals (local-only cache; obtain from internal source or NotebookLM)
docs/guide/*.docx
```

- [ ] **Step 1.5: Move docx manuals**

```bash
mv "tmp/guide/Illumio Agent部署手冊_20250815.docx" docs/guide/
mv "tmp/guide/Illumio_PCE操作手冊_20251128.docx" docs/guide/
rmdir tmp/guide
```

Verify:

```bash
ls "docs/guide/" | wc -l        # expect 2 docx (plus .gitkeep)
git check-ignore -v "docs/guide/Illumio Agent部署手冊_20250815.docx"
```

Expected: `.gitignore` rule shown; docx not in `git status`.

- [ ] **Step 1.6: Write `scripts/check-sop-template.sh` validator**

```bash
mkdir -p scripts
```

Create file with EXACT content:

```bash
#!/usr/bin/env bash
# Validate every docs/{pce,ven,cert,platform}/*.md has the required 7 sections.
# Exit 0 if all pass; non-zero with file:section list on failure.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
fail=0
REQUIRED=(
  '^## 1\. 目的與適用情境'
  '^## 2\. 前置條件'
  '^## 3\. 操作步驟'
  '^## 4\. 驗證'
  '^## 5\. 失敗回滾'
  '^## 6\. 原廠文件參照'
  '^## 7\. 與原廠差異'
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
```

Then:

```bash
chmod +x scripts/check-sop-template.sh
```

- [ ] **Step 1.7: Run validator (expect 0 SOPs found, exit 0)**

```bash
./scripts/check-sop-template.sh
```

Expected: `OK: all SOPs have §1–§7` (vacuously true with no files).

- [ ] **Step 1.8: Verify staging looks right**

```bash
git status --short
```

Expected: `??` markers for `docs/` (5 dirs + SOP-TEMPLATE.md + README.md), `scripts/`, modified `.gitignore`. **No** docx in the list.

- [ ] **Step 1.9: Commit (commit 1)**

```bash
git add docs/ scripts/ .gitignore
git commit -m "$(cat <<'EOF'
feat(docs): scaffold docs/ tree, SOP template, and gitignore vendor manuals

- Add docs/{pce,ven,cert,platform,guide}/ with .gitkeep
- Add docs/SOP-TEMPLATE.md (7-section canonical template)
- Add docs/README.md stub (full index in stage 4)
- Add scripts/check-sop-template.sh validator
- Move tmp/guide/ vendor docx to docs/guide/ (gitignored)
- Add docs/guide/*.docx to .gitignore

Stage 1 of 4 per docs/superpowers/specs/2026-05-29-illumio-sop-integration-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Stage 2 — Migrate 21 SOPs (single commit at end)

> **General migration procedure** (apply to every file in Tasks 2a–2d):
>
> 1. Read `tmp/<source>.txt` (use `Read` tool, not Bash `cat`).
> 2. Create `docs/<category>/<target>.md` using the SOP template.
> 3. **Frontmatter**: fill `原始檔` with the source filename. Set `更新日期` to `2026-05-29`. Leave 適用版本 as `Illumio PCE 25.x / VEN 25.x（依驗證結果填）` — verified in Stage 3.
> 4. **§1 目的**: write one Traditional Chinese sentence summarising what the source SOP achieves. Read the source carefully — the title alone is not enough.
> 5. **§2 前置條件**: extract any "before you start" / "prerequisites" content from the source. If none stated, write `- — 無 —`.
> 6. **§3 操作步驟**: paste the original commands **verbatim** inside a ```bash fenced block. Keep the ordering. Add brief 繁中 comments only where the command's purpose is non-obvious. **Do not modify command flags, paths, or order.**
> 7. **§4 驗證**: extract verification / sanity check commands from the source. If none, write `- — 無 —` (NotebookLM may fill in Stage 3).
> 8. **§5 失敗回滾 / 救援**: if the source covers rollback, summarise; else `- — 無 —`.
> 9. **§6 / §7**: leave intentionally empty stubs:
>    - `## 6. 原廠文件參照\n\n*（Stage 3 待填）*\n`
>    - `## 7. 與原廠差異（若有）\n\n*（Stage 3 待填）*\n`
> 10. Do NOT commit per-file — accumulate, validate at end of stage, then one commit.
>
> **Special cases:**
> - `pce_remove_ndoe.txt` (typo) → `pce/remove-node.md` (spelling corrected)
> - `illumilo_k8s_init.txt` (typo) → `platform/k8s-init.md`
> - `ilumio FlowLink SOP.txt` (typo + space) → `platform/flowlink.md`; use quoted source path
> - `DigiCert_Global_Root_Linux.txt` / `_windows.txt`: these contain root CA certs to import. §3 should keep the cert-import commands; the PEM block can stay inside §3 fence.
> - `openssl_cert-sign.txt`: very short (1.4 KB) — likely one openssl command. Keep verbatim.

### Task 2a: PCE category (7 files)

**Files (create):**
- `docs/pce/snc-setup.md` ← `tmp/illumio_pce_snc_setup_v3.txt`
- `docs/pce/mnc-setup.md` ← `tmp/illumio_pce_mnc_setup_v4.txt`
- `docs/pce/upgrade.md` ← `tmp/illumio_pce_upgrade_snc.txt`
- `docs/pce/backup.md` ← `tmp/illumio_backup_v4.txt`
- `docs/pce/vulnerability.md` ← `tmp/illumio_pce_vulnerability.txt`
- `docs/pce/network-setting.md` ← `tmp/illumio_snc_network_setting.txt`
- `docs/pce/remove-node.md` ← `tmp/pce_remove_ndoe.txt`

- [ ] **Step 2a.1: Migrate `snc-setup.md`** — Read tmp/illumio_pce_snc_setup_v3.txt, apply procedure above. 標題: `# Illumio PCE SNC 安裝（單一節點）`.
- [ ] **Step 2a.2: Migrate `mnc-setup.md`** — Read tmp/illumio_pce_mnc_setup_v4.txt. 標題: `# Illumio PCE MNC 安裝（多節點叢集）`.
- [ ] **Step 2a.3: Migrate `upgrade.md`** — Read tmp/illumio_pce_upgrade_snc.txt. 標題: `# Illumio PCE SNC 升級程序`.
- [ ] **Step 2a.4: Migrate `backup.md`** — Read tmp/illumio_backup_v4.txt. 標題: `# Illumio PCE 備份程序`.
- [ ] **Step 2a.5: Migrate `vulnerability.md`** — Read tmp/illumio_pce_vulnerability.txt. 標題: `# Illumio PCE 漏洞處理`. 註：來源僅 444 B，可能極簡。
- [ ] **Step 2a.6: Migrate `network-setting.md`** — Read tmp/illumio_snc_network_setting.txt. 標題: `# Illumio PCE SNC 網路設定`.
- [ ] **Step 2a.7: Migrate `remove-node.md`** — Read tmp/pce_remove_ndoe.txt. 標題: `# Illumio PCE 節點移除`.
- [ ] **Step 2a.8: Run validator on PCE files**

```bash
./scripts/check-sop-template.sh
```

Expected: `OK: all SOPs have §1–§7` (7 PCE files pass).

### Task 2b: VEN category (6 files)

**Files (create):**
- `docs/ven/install-linux.md` ← `tmp/illumio_ven_linux_install.txt`
- `docs/ven/install-windows.md` ← `tmp/illumio_ven_win_install.txt`
- `docs/ven/install-aix.md` ← `tmp/illumio_ven_aix_install.txt`
- `docs/ven/uninstall-aix.md` ← `tmp/illumio_ven_aix_uninstall.txt`
- `docs/ven/proxy-pairprofile.md` ← `tmp/Illumio_ven_proxy_pairprofile.txt`
- `docs/ven/rule-hit-count.md` ← `tmp/illumio_rulehitcount.txt`

- [ ] **Step 2b.1: Migrate `install-linux.md`** — 標題: `# Illumio VEN — Linux 手動安裝`. 在 §1 末段加一句：「自動化版本見 [`../../linux/manual_deploy/deploy-illumio.sh`](../../linux/manual_deploy/deploy-illumio.sh) 與 [`../../linux/pairing_prereq/prepare-and-pair.sh`](../../linux/pairing_prereq/prepare-and-pair.sh)。」
- [ ] **Step 2b.2: Migrate `install-windows.md`** — 標題: `# Illumio VEN — Windows 手動安裝`. §1 加：「自動化版本見 [`../../windows/manual_deploy/Deploy-Illumio.ps1`](../../windows/manual_deploy/Deploy-Illumio.ps1)。」
- [ ] **Step 2b.3: Migrate `install-aix.md`** — 標題: `# Illumio VEN — AIX 手動安裝`. §1 加：「目前 aix/ 僅有 README.md 說明，無自動腳本。」
- [ ] **Step 2b.4: Migrate `uninstall-aix.md`** — 標題: `# Illumio VEN — AIX 解除安裝`.
- [ ] **Step 2b.5: Migrate `proxy-pairprofile.md`** — 標題: `# Illumio VEN — 透過 Proxy 配對與 Pairing Profile`.
- [ ] **Step 2b.6: Migrate `rule-hit-count.md`** — 標題: `# Illumio Rule Hit Count（規則命中計數查詢）`.
- [ ] **Step 2b.7: Run validator**

```bash
./scripts/check-sop-template.sh
```

Expected: 13 files pass.

### Task 2c: Cert category (3 files)

**Files (create):**
- `docs/cert/digicert-root-linux.md` ← `tmp/DigiCert_Global_Root_Linux.txt`
- `docs/cert/digicert-root-windows.md` ← `tmp/DigiCert_Global_Root_windows.txt`
- `docs/cert/openssl-cert-sign.md` ← `tmp/openssl_cert-sign.txt`

- [ ] **Step 2c.1: Migrate `digicert-root-linux.md`** — 標題: `# DigiCert Global Root CA 匯入（Linux）`. §3 fenced block 保留 PEM 與 update-ca-trust / update-ca-certificates 指令逐字。
- [ ] **Step 2c.2: Migrate `digicert-root-windows.md`** — 標題: `# DigiCert Global Root CA 匯入（Windows）`. §3 保留 certutil / Import-Certificate 指令。
- [ ] **Step 2c.3: Migrate `openssl-cert-sign.md`** — 標題: `# OpenSSL 自簽憑證程序`. 因來源僅 1.4 KB，§3 應是一兩條 openssl 指令。
- [ ] **Step 2c.4: Run validator**

```bash
./scripts/check-sop-template.sh
```

Expected: 16 files pass.

### Task 2d: Platform category (5 files)

**Files (create):**
- `docs/platform/k8s.md` ← `tmp/illumio_k8s.txt`
- `docs/platform/k8s-init.md` ← `tmp/illumilo_k8s_init.txt`
- `docs/platform/flowlink.md` ← `tmp/ilumio FlowLink SOP.txt`
- `docs/platform/linux-emergency-mode.md` ← `tmp/linux_emergency_mode_sop.txt`
- `docs/platform/redhat-lvm.md` ← `tmp/illumio_Redhat_LVM_SOP.txt`

- [ ] **Step 2d.1: Migrate `k8s.md`** — 標題: `# Illumio Core for Kubernetes 部署`. Read tmp/illumio_k8s.txt.
- [ ] **Step 2d.2: Migrate `k8s-init.md`** — 標題: `# Illumio Kubernetes 初始化作業`. Read tmp/illumilo_k8s_init.txt (note typo in source name).
- [ ] **Step 2d.3: Migrate `flowlink.md`** — 標題: `# Illumio FlowLink SOP`. Read `tmp/ilumio FlowLink SOP.txt` (quoted path because of space + typo).
- [ ] **Step 2d.4: Migrate `linux-emergency-mode.md`** — 標題: `# Linux Emergency Mode 進入與修復`. Note: 內容可能不專屬 Illumio，是 Linux 本身的救援程序。
- [ ] **Step 2d.5: Migrate `redhat-lvm.md`** — 標題: `# RedHat LVM 調整（Illumio PCE 場景）`.
- [ ] **Step 2d.6: Run validator on all 21 files**

```bash
./scripts/check-sop-template.sh
```

Expected: `OK: all SOPs have §1–§7`. Exit 0.

### Task 2e: Stage 2 commit (commit 2)

- [ ] **Step 2e.1: Stage and verify**

```bash
git status --short
git add docs/pce/*.md docs/ven/*.md docs/cert/*.md docs/platform/*.md
git diff --cached --stat
```

Expected: 21 new files; line counts roughly tracking the source `.txt` sizes plus template overhead.

- [ ] **Step 2e.2: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs(sop): migrate 21 SOPs from tmp/ to docs/ with unified template

- PCE: snc-setup, mnc-setup, upgrade, backup, vulnerability,
       network-setting, remove-node (7)
- VEN: install-{linux,windows,aix}, uninstall-aix,
       proxy-pairprofile, rule-hit-count (6)
- Cert: digicert-root-{linux,windows}, openssl-cert-sign (3)
- Platform: k8s, k8s-init, flowlink, linux-emergency-mode,
            redhat-lvm (5)

§1–§5 populated from source .txt. §6/§7 left as stage-3 stubs.
Original commands preserved verbatim in §3 fenced blocks.

Stage 2 of 4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Stage 3 — NotebookLM Verification (single commit at end)

> **General verification procedure** (apply to every `.md` in Tasks 3a–3d):
>
> 1. Read the `.md` file (use `Read`).
> 2. Extract §1–§5 plain text (strip the `>` frontmatter, keep §3 fenced commands).
> 3. Build the NotebookLM prompt by inserting that text into the template below.
> 4. Call: `notebooklm ask "<prompt>" -n 8c325126-bc83-4c86-8c6e-8759a242928e --json`
>    - Use `--retry 3` for transient rate limits.
>    - **Do not** use `--save-as-note` (避免污染原廠筆記).
> 5. Parse the `answer` field. Look for: vendor chapter citations, missing-from-vendor flags, vendor-conflicts, vendor-only steps.
> 6. **Web fallback** if any of these are true:
>    - answer contains 「資料庫無」/「無相關」/「找不到」/「I cannot find」
>    - `references` array is empty
>    - SOP is high-risk (backup, upgrade, vulnerability, remove-node) and no concrete page/section was cited
>
>    Then:
>    - WebFetch `https://docs.illumio.com/` with a targeted prompt (e.g. "Find the backup procedure for PCE 25.4").
>    - If unknown URL: `WebSearch site:docs.illumio.com <keywords>` → take top 2 → WebFetch each.
> 7. **Edit the .md**:
>    - Replace `*（Stage 3 待填）*` under §6 with bullet list. Format: `- [NotebookLM] <source-title> §<chapter/section> — <one-line excerpt>` or `- [Web] <URL> — <topic>`.
>    - Replace `*（Stage 3 待填）*` under §7 with bullet list of concrete deltas, or with a single line `- 驗證結果與原廠一致` if no delta found.
>    - Update frontmatter `**適用版本**` line to the actual version observed (e.g. `Illumio PCE 25.4 / VEN 25.4`).
> 8. Do NOT commit per-file — batch at end of stage.
>
> **NotebookLM prompt template (insert as the `ask` argument):**
>
> ```
> 我有一份內部 SOP 叫「<檔名>」，內容如下：
>
> <SOP §1–§5 純文字>
>
> 請對照你資料庫裡的 Illumio 25.4 官方文件（Install_Upgrade Guide、Admin_25_4、PCE 操作手冊、Agent 部署手冊等），回答：
>
> 1. 本 SOP 哪些步驟與原廠**完全一致**？引用具體章節 / 頁碼。
> 2. 哪些步驟是原廠沒有、SOP 自行**補強**？這些補強合理嗎？
> 3. 哪些步驟與原廠**做法不同**？列差異與可能原因（環境限制 / 版本 / 錯誤）。
> 4. 哪些**原廠必要步驟** SOP 沒寫到？
>
> 請只引用你資料庫裡有的官方文件，不要外推；找不到就明說「資料庫無相關內容」。
> ```
>
> **Pacing:** Between consecutive `ask` calls, `sleep 5` to be polite. If rate-limit error: `sleep 300` and retry once.

### Task 3a: Verify PCE category (7 files)

- [ ] **Step 3a.1: Verify `docs/pce/snc-setup.md`** — install/upgrade guide is primary source. Look for `Install_Upgrad…` citations.
- [ ] **Step 3a.2: Verify `docs/pce/mnc-setup.md`** — same source pool plus `Admin_25_4.pdf` MNC topology section.
- [ ] **Step 3a.3: Verify `docs/pce/upgrade.md`** — Install_Upgrade guide upgrade chapter.
- [ ] **Step 3a.4: Verify `docs/pce/backup.md`** — Admin_25_4 backup chapter; **high-risk → Web fallback if no page cited.**
- [ ] **Step 3a.5: Verify `docs/pce/vulnerability.md`** — likely no direct vendor chapter; expect heavy web fallback.
- [ ] **Step 3a.6: Verify `docs/pce/network-setting.md`** — `Illumio_PCE操作手冊` 網路設定章節.
- [ ] **Step 3a.7: Verify `docs/pce/remove-node.md`** — MNC ops chapter in Admin_25_4 or PCE 操作手冊.
- [ ] **Step 3a.8: Run validator** — `./scripts/check-sop-template.sh` (expect pass).

### Task 3b: Verify VEN category (6 files)

- [ ] **Step 3b.1: Verify `docs/ven/install-linux.md`** — `Illumio Agent部署手冊` Linux 章節.
- [ ] **Step 3b.2: Verify `docs/ven/install-windows.md`** — `Illumio Agent部署手冊` Windows 章節.
- [ ] **Step 3b.3: Verify `docs/ven/install-aix.md`** — `Illumio Agent部署手冊` AIX 章節（若有；可能要 web fallback）.
- [ ] **Step 3b.4: Verify `docs/ven/uninstall-aix.md`** — Agent 部署手冊解除安裝 / `Admin_25_4` VEN management.
- [ ] **Step 3b.5: Verify `docs/ven/proxy-pairprofile.md`** — Pairing Profile + Proxy 章節（兩份手冊都可能涵蓋）.
- [ ] **Step 3b.6: Verify `docs/ven/rule-hit-count.md`** — `Visualization_…` / `REST_APIs_25_4` 章節（可能要 API 章節）.
- [ ] **Step 3b.7: Run validator**.

### Task 3c: Verify Cert category (3 files)

- [ ] **Step 3c.1: Verify `docs/cert/digicert-root-linux.md`** — 原廠手冊通常不教 OS 層 CA 信任；預期主要為 [Web] 來源（DigiCert 官網或 docs.illumio.com TLS 章節）.
- [ ] **Step 3c.2: Verify `docs/cert/digicert-root-windows.md`** — 同上.
- [ ] **Step 3c.3: Verify `docs/cert/openssl-cert-sign.md`** — 原廠手冊可能教 PCE TLS cert；NotebookLM 找 `Install_Upgrade` 的 TLS / Web Console Certificate 章節。
- [ ] **Step 3c.4: Run validator**.

### Task 3d: Verify Platform category (5 files)

- [ ] **Step 3d.1: Verify `docs/platform/k8s.md`** — `Illumio Core for K8 and OS Product Brief.pdf` + `kubernetes-ope…` + `適用Kubernetes… Core.pdf`.
- [ ] **Step 3d.2: Verify `docs/platform/k8s-init.md`** — 同上 source pool；可能找 `MicroK8s Illumio 支援性諮詢`.
- [ ] **Step 3d.3: Verify `docs/platform/flowlink.md`** — FlowLink 在 NotebookLM 可能無直接來源；預期 web fallback `site:docs.illumio.com flowlink`.
- [ ] **Step 3d.4: Verify `docs/platform/linux-emergency-mode.md`** — 非 Illumio 主題；§6 註記「Illumio 原廠文件無相關內容；參考 [Web] RHEL emergency mode 官方說明」.
- [ ] **Step 3d.5: Verify `docs/platform/redhat-lvm.md`** — 同上：RHEL LVM 是 OS 層；§6 標 [Web] + RHEL 官方參考。
- [ ] **Step 3d.6: Run validator**.

### Task 3e: Stage 3 commit (commit 3)

- [ ] **Step 3e.1: Sanity check — every .md has §6/§7 substantive content**

```bash
# Both §6 and §7 must not still say "（Stage 3 待填）"
if grep -l "Stage 3 待填" docs/{pce,ven,cert,platform}/*.md; then
  echo "FAIL: some files still have stage-3 placeholders"; exit 1
fi
# Every §6 has at least one [NotebookLM] or [Web] tag
for f in docs/{pce,ven,cert,platform}/*.md; do
  if ! awk '/^## 6\./{flag=1;next} /^## 7\./{flag=0} flag' "$f" | grep -qE '\[NotebookLM\]|\[Web\]'; then
    echo "MISSING vendor ref: $f"
  fi
done
```

Expected: no `FAIL` output, no `MISSING vendor ref` lines.

- [ ] **Step 3e.2: Stage and commit**

```bash
git add docs/{pce,ven,cert,platform}/*.md
git diff --cached --stat
git commit -m "$(cat <<'EOF'
docs(sop): cross-reference 21 SOPs against vendor docs via NotebookLM

For each SOP, queried NotebookLM "Illumio" (8c325126…) for chapter
citations, then filled §6 (vendor refs) and §7 (deltas). Web fallback
to docs.illumio.com used where the notebook had no coverage
(FlowLink, OS-layer topics like emergency mode and LVM).

Adopted versions and concrete deltas (e.g. environment-specific paths,
extra safety steps) are noted in each §7. Where no delta exists, §7
reads "驗證結果與原廠一致".

Stage 3 of 4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Stage 4 — Finalize

**Files:**
- Rewrite: `docs/README.md` (replace stub with full index)
- Modify: `README.md` (top-level — add `docs/` section to directory layout, in both English and 繁體中文 blocks)
- Delete: `tmp/*.txt` (21 files); `tmp/` directory if empty after

- [ ] **Step 4.1: Rewrite `docs/README.md`**

Replace its entire content with:

````markdown
# Illumio 維運 SOP

> 本目錄收錄 Illumio PCE / VEN / 憑證 / 平台整合相關的標準作業程序（SOP）。
> 模板與規則見 [SOP-TEMPLATE.md](./SOP-TEMPLATE.md)；驗證流程見
> [設計 spec](./superpowers/specs/2026-05-29-illumio-sop-integration-design.md)。

## 目錄

### PCE 伺服器端 (`pce/`)
| 主題 | 檔案 |
|---|---|
| SNC 單節點安裝 | [snc-setup.md](./pce/snc-setup.md) |
| MNC 多節點安裝 | [mnc-setup.md](./pce/mnc-setup.md) |
| 升級程序 | [upgrade.md](./pce/upgrade.md) |
| 備份程序 | [backup.md](./pce/backup.md) |
| 漏洞處理 | [vulnerability.md](./pce/vulnerability.md) |
| 網路設定 | [network-setting.md](./pce/network-setting.md) |
| 節點移除 | [remove-node.md](./pce/remove-node.md) |

### VEN 端點 (`ven/`)
| 主題 | 檔案 |
|---|---|
| Linux 手動安裝 | [install-linux.md](./ven/install-linux.md) |
| Windows 手動安裝 | [install-windows.md](./ven/install-windows.md) |
| AIX 手動安裝 | [install-aix.md](./ven/install-aix.md) |
| AIX 解除安裝 | [uninstall-aix.md](./ven/uninstall-aix.md) |
| Proxy + Pairing Profile | [proxy-pairprofile.md](./ven/proxy-pairprofile.md) |
| Rule Hit Count 查詢 | [rule-hit-count.md](./ven/rule-hit-count.md) |

> 自動化部署腳本見 [`../linux/`](../linux/)、[`../windows/`](../windows/)、[`../aix/`](../aix/)。

### 憑證與 SSL (`cert/`)
| 主題 | 檔案 |
|---|---|
| DigiCert Root CA（Linux） | [digicert-root-linux.md](./cert/digicert-root-linux.md) |
| DigiCert Root CA（Windows） | [digicert-root-windows.md](./cert/digicert-root-windows.md) |
| OpenSSL 自簽憑證 | [openssl-cert-sign.md](./cert/openssl-cert-sign.md) |

### 平台與整合 (`platform/`)
| 主題 | 檔案 |
|---|---|
| Kubernetes 部署 | [k8s.md](./platform/k8s.md) |
| Kubernetes 初始化 | [k8s-init.md](./platform/k8s-init.md) |
| FlowLink SOP | [flowlink.md](./platform/flowlink.md) |
| Linux Emergency Mode | [linux-emergency-mode.md](./platform/linux-emergency-mode.md) |
| RedHat LVM 調整 | [redhat-lvm.md](./platform/redhat-lvm.md) |

### 原廠手冊 (`guide/`)
本目錄存放原廠中文手冊本機快取，**內容不入 git**（`.gitignore` 排除）：

- `Illumio Agent部署手冊_20250815.docx`
- `Illumio_PCE操作手冊_20251128.docx`

取得方式：
1. 內部來源 / 同事提供
2. NotebookLM「Illumio」筆記（ID `8c325126-bc83-4c86-8c6e-8759a242928e`）內收錄；
   `notebooklm source list -n 8c325126-bc83-4c86-8c6e-8759a242928e` 可看到對應 source。

## 原 tmp/ 對映（歷史參考）

下表記錄遷移前的舊檔名 → 新位置：

| 原 tmp/ 檔名 | 新位置 |
|---|---|
| `illumio_pce_snc_setup_v3.txt` | `pce/snc-setup.md` |
| `illumio_pce_mnc_setup_v4.txt` | `pce/mnc-setup.md` |
| `illumio_pce_upgrade_snc.txt` | `pce/upgrade.md` |
| `illumio_backup_v4.txt` | `pce/backup.md` |
| `illumio_pce_vulnerability.txt` | `pce/vulnerability.md` |
| `illumio_snc_network_setting.txt` | `pce/network-setting.md` |
| `pce_remove_ndoe.txt` | `pce/remove-node.md` |
| `illumio_ven_linux_install.txt` | `ven/install-linux.md` |
| `illumio_ven_win_install.txt` | `ven/install-windows.md` |
| `illumio_ven_aix_install.txt` | `ven/install-aix.md` |
| `illumio_ven_aix_uninstall.txt` | `ven/uninstall-aix.md` |
| `Illumio_ven_proxy_pairprofile.txt` | `ven/proxy-pairprofile.md` |
| `illumio_rulehitcount.txt` | `ven/rule-hit-count.md` |
| `DigiCert_Global_Root_Linux.txt` | `cert/digicert-root-linux.md` |
| `DigiCert_Global_Root_windows.txt` | `cert/digicert-root-windows.md` |
| `openssl_cert-sign.txt` | `cert/openssl-cert-sign.md` |
| `illumio_k8s.txt` | `platform/k8s.md` |
| `illumilo_k8s_init.txt` | `platform/k8s-init.md` |
| `ilumio FlowLink SOP.txt` | `platform/flowlink.md` |
| `linux_emergency_mode_sop.txt` | `platform/linux-emergency-mode.md` |
| `illumio_Redhat_LVM_SOP.txt` | `platform/redhat-lvm.md` |

> 原 `tmp/` 為 `.gitignore` 排除目錄，自始未入 git；
> 原指令文字已逐字併入各 `.md` 的 §3 fenced block，是版控起點。

## 新增 SOP

複製 [`SOP-TEMPLATE.md`](./SOP-TEMPLATE.md)，依模板強制規則填寫。提交前跑：

```bash
./scripts/check-sop-template.sh
```
````

- [ ] **Step 4.2: Update top-level `README.md`** — add `docs/` to the directory tree

Modify `README.md` in both the English and 繁體中文 sections. Find the existing `## 目錄結構` / `## Directory Structure` blocks and append the docs/ subtree.

Read the file first to find exact line numbers, then make the edits. Each block currently shows the `linux/`, `windows/`, `aix/` trees. Add (in both locations):

```
docs/
├── README.md              # 索引
├── SOP-TEMPLATE.md        # SOP 模板
├── pce/                   # PCE 伺服器端 SOP (7 份)
├── ven/                   # VEN 端點 SOP (6 份)
├── cert/                  # 憑證與 SSL (3 份)
├── platform/              # K8s / FlowLink / Linux (5 份)
└── guide/                 # 原廠手冊本機快取 (gitignored)
```

And in the English block:

```
docs/
├── README.md              # Index
├── SOP-TEMPLATE.md        # SOP template
├── pce/                   # PCE server-side SOPs (7 docs)
├── ven/                   # VEN endpoint SOPs (6 docs)
├── cert/                  # Certificates & SSL (3 docs)
├── platform/              # K8s / FlowLink / Linux (5 docs)
└── guide/                 # Vendor manuals local cache (gitignored)
```

Add a one-liner under the existing intro of each section: 「完整索引見 [`docs/README.md`](docs/README.md)」 / "Full index: [`docs/README.md`](docs/README.md)".

- [ ] **Step 4.3: Delete migrated tmp/ .txt files**

```bash
rm tmp/*.txt
rmdir tmp 2>/dev/null || ls tmp/   # if non-empty, list what's left and stop
```

If anything other than `.txt` remains, surface it to the user — don't auto-delete.

- [ ] **Step 4.4: Final verification suite**

```bash
# All 21 SOPs still pass template check
./scripts/check-sop-template.sh

# No stage-3 placeholders remain
! grep -rn "Stage 3 待填" docs/{pce,ven,cert,platform}/

# Top-level README references docs/
grep -c 'docs/' README.md

# Tree shape
find docs -maxdepth 2 -type f | sort
ls docs/guide/                # should still contain 2 docx locally
git check-ignore -v "docs/guide/Illumio Agent部署手冊_20250815.docx"

# No tmp/ left
[ ! -d tmp ] && echo "OK: tmp/ removed" || ls tmp/
```

Expected: all checks pass, `tmp/` removed, docx still on disk but ignored.

- [ ] **Step 4.5: Commit (commit 4)**

```bash
git add docs/README.md README.md
git rm -r --ignore-unmatch tmp/ 2>/dev/null || true   # tmp/ was never tracked, so this is a no-op; the actual deletion happened on disk in 4.3
git status --short
git commit -m "$(cat <<'EOF'
docs(sop): finalize index, top-level README, and remove tmp/

- docs/README.md: full categorised index of 21 SOPs + tmp/ → docs/ mapping
- README.md: add docs/ block to both English and 繁體中文 directory trees
- Delete tmp/*.txt (v0 content lives in docs/**/*.md §3)

Stage 4 of 4 — completes docs/superpowers/specs/2026-05-29-illumio-sop-integration-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4.6: Verify 4-commit history**

```bash
git log --oneline -5
```

Expected: 4 new commits on top of `9f35a8b docs(spec): ...`:
```
<sha4> docs(sop): finalize index, top-level README, and remove tmp/
<sha3> docs(sop): cross-reference 21 SOPs against vendor docs via NotebookLM
<sha2> docs(sop): migrate 21 SOPs from tmp/ to docs/ with unified template
<sha1> feat(docs): scaffold docs/ tree, SOP template, and gitignore vendor manuals
9f35a8b docs(spec): add Illumio SOP integration & version control design
```

---

## Definition of Done (from spec §10)

- [ ] 21 `.md` exist in `docs/{pce,ven,cert,platform}/` and pass `check-sop-template.sh`
- [ ] Every `.md` §6 has at least one `[NotebookLM]` or `[Web]` source
- [ ] `docs/README.md` lists all 21 + the tmp→docs mapping + `docs/guide/` instructions
- [ ] `docs/guide/` has 2 docx on disk (local-only), `.gitignore` includes `docs/guide/*.docx`
- [ ] Top-level `README.md` mentions `docs/` in both languages
- [ ] `tmp/` removed
- [ ] 4 conventional-format English commits, reviewable in `git log --oneline -5`
