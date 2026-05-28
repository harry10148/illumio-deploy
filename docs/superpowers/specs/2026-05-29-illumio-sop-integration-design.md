# Illumio SOP 整合與版本控管設計

- **建立日期**：2026-05-29
- **作者**：harry（with Claude）
- **狀態**：草案，待 review
- **後續**：通過後改用 superpowers:writing-plans 產出實作計畫

## 1. 背景

`illumio-deploy/tmp/` 目錄已累積：

- **21 份**個人手工整理的 SOP 文字檔（範圍橫跨 PCE 伺服器、VEN 端點、憑證、
  平台整合 K8s/FlowLink/Linux），檔名／格式不一致、無交叉索引、未經原廠文件覆核。
- **`tmp/guide/` 子目錄 2 份原廠中文 docx 母本**（總 ~68 MB）：
  `Illumio Agent部署手冊_20250815.docx`、`Illumio_PCE操作手冊_20251128.docx`，
  即 NotebookLM 「Illumio」筆記內對應來源的源檔。

**重要前提**：`.gitignore` 第 23 行已將整個 `tmp/` 目錄排除——
所以 21 份 .txt 和 2 份 docx **從未進入 git**。本案不依賴 git 歷史回溯原 .txt
（原指令文字會逐字保留在新 .md 的 §3，是 v0 的真實版控起點）。

專案目前只覆蓋「VEN 自動化部署腳本（linux/windows/aix）」，
SOP 內容遠超出腳本能涵蓋的範疇。

本案目標：把 21 份 SOP 升級成可版本控管的 Markdown 文件、
依主題分類、並以 NotebookLM 「Illumio」筆記（含 103 份原廠來源）逐份對照，
產出附「原廠參照／差異」的可靠維運手冊集；同時把 2 份原廠 docx
搬到 `docs/guide/` 但透過 `.gitignore` 排除入庫（保留本機查閱、不污染 repo size）。

## 2. 不在範圍

- 改寫 / 重構 `linux/`, `windows/`, `aix/` 既有部署腳本。
- 修正 SOP 內步驟的「對錯」——只標註差異，不擅自改動現場實踐。
- 翻譯為英文／日文等其他語言。

## 3. 目錄結構（核准案）

```
illumio-deploy/
├── linux/      (沿用)
├── windows/    (沿用)
├── aix/        (沿用)
└── docs/
    ├── README.md                    ← 總索引（4 大類目錄、檔名對映、查找路徑）
    ├── SOP-TEMPLATE.md              ← SOP 模板說明文件（給未來新增者參考）
    ├── pce/                         (7 份)
    │   ├── snc-setup.md
    │   ├── mnc-setup.md
    │   ├── upgrade.md
    │   ├── backup.md
    │   ├── vulnerability.md
    │   ├── network-setting.md
    │   └── remove-node.md
    ├── ven/                         (6 份)
    │   ├── install-linux.md
    │   ├── install-windows.md
    │   ├── install-aix.md
    │   ├── uninstall-aix.md
    │   ├── proxy-pairprofile.md
    │   └── rule-hit-count.md
    ├── cert/                        (3 份)
    │   ├── digicert-root-linux.md
    │   ├── digicert-root-windows.md
    │   └── openssl-cert-sign.md
    ├── platform/                    (5 份)
    │   ├── k8s.md
    │   ├── k8s-init.md
    │   ├── flowlink.md
    │   ├── linux-emergency-mode.md
    │   └── redhat-lvm.md
    └── guide/                       (本機查閱用，gitignore 排除)
        ├── Illumio Agent部署手冊_20250815.docx
        └── Illumio_PCE操作手冊_20251128.docx
```

> SOP 總計：PCE 7 + VEN 6 + cert 3 + platform 5 = **21 份**。
> `docs/guide/` 為原廠 docx 母本本機快取，**不入 git**。

### 3.1 原廠 docx 母本（docs/guide/）

`tmp/guide/` 下兩份原廠中文手冊用普通 `mv`（不用 `git mv`，因 tmp/ 在 gitignore
排除清單）搬到 `docs/guide/`，並把 `docs/guide/*.docx` 加入 `.gitignore`：

```
# docs/guide/ 為原廠手冊本機快取，不入 git
docs/guide/*.docx
```

`docs/guide/.gitkeep`（空檔）讓目錄結構入 git，供 README 連結與
NotebookLM 路徑說明用。`docs/README.md` 會說明：

- 兩份 docx 從何處取得（內部來源 / 同事）
- NotebookLM「Illumio」筆記（`8c325126…`）已收錄該兩份手冊
- 若本機缺檔，可從 NotebookLM `source list -n 8c325126…` 找到對應 source 重新下載

### 3.2 來源檔對映（原 tmp/ → docs/）

| 原檔（tmp/） | 目標（docs/） |
|---|---|
| `illumio_pce_snc_setup_v3.txt` | `pce/snc-setup.md` |
| `illumio_pce_mnc_setup_v4.txt` | `pce/mnc-setup.md` |
| `illumio_pce_upgrade_snc.txt` | `pce/upgrade.md` |
| `illumio_backup_v4.txt` | `pce/backup.md` |
| `illumio_pce_vulnerability.txt` | `pce/vulnerability.md` |
| `illumio_snc_network_setting.txt` | `pce/network-setting.md` |
| `pce_remove_ndoe.txt`（原檔名 typo） | `pce/remove-node.md` |
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
| `illumilo_k8s_init.txt`（原檔名 typo） | `platform/k8s-init.md` |
| `ilumio FlowLink SOP.txt`（原檔名 typo + 空白） | `platform/flowlink.md` |
| `linux_emergency_mode_sop.txt` | `platform/linux-emergency-mode.md` |
| `illumio_Redhat_LVM_SOP.txt` | `platform/redhat-lvm.md` |

> **原始檔名 typo 處理**：`illumilo` / `ndoe` / `ilumio` 等錯字
> 在新檔名一律拼正；舊檔名只在本對映表與每份 .md frontmatter 的
> 「原始檔」欄位留下紀錄（tmp/ 本身不入 git，故無 git mv 歷史可追）。

## 4. SOP 統一模板

每份 `docs/**/*.md` 必須遵守此七段結構（外層用 4 個 backtick 包住，避免內層
\`\`\`bash 提前關閉）：

````markdown
# <SOP 標題（繁中）>

> **適用版本**：Illumio PCE 25.x / VEN 25.x（依驗證結果填）
> **更新日期**：2026-05-29
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
````

### 4.1 模板強制規則

- 段號 §1–§7 必須齊全；無內容寫「— 無 —」。
- 步驟區（§3）的指令逐字保留**原 SOP** 內容，不擅自改動（差異走 §7 註記）。
- §6 來源標籤：`[NotebookLM]` / `[Web]` / `[現場]` 三選一，混用標明。
- §7 若實際無差異，仍須保留段標並寫「驗證結果與原廠一致」。

## 5. 執行流程（4 階段、單 PR、4 commits）

### 階段 1 — 骨架（commit 1）
- 建 `docs/{pce,ven,cert,platform,guide}/`
- 寫 `docs/SOP-TEMPLATE.md`（即 §4 模板說明）
- 暫時 stub 一個 `docs/README.md`（總索引在階段 4 完成）
- 更新 `.gitignore`：新增 `docs/guide/*.docx` 一行；既有的 `tmp/` 整目錄排除規則保留
  （未來臨時檔仍可用 tmp/，但本案會在階段 4 把目錄刪除）
- 將 `tmp/guide/*.docx` 用 `mv` 搬到 `docs/guide/`（注意：源在 gitignore 內，
  不能用 `git mv`，會報 `not under version control`）
- 建 `docs/guide/.gitkeep` + 一行 README 說明手冊出處

> commit 內容只包含：新增的 docs/ 目錄 + .gitkeep + SOP-TEMPLATE.md + stub README.md
> + .gitignore 變更；**docx 不入庫**（仍被忽略）。

### 階段 2 — 遷移（commit 2）
- 21 份 `tmp/*.txt` → 21 份 `docs/**/*.md`，套模板 §1–§5
- §6 / §7 留空待階段 3 填
- `tmp/` 上層 .txt **保留**到階段 4 結束才刪（驗證階段需要 diff）

### 階段 3 — NotebookLM + Web 驗證（commit 3）
- 對 21 份 SOP，逐份對 NotebookLM `Illumio`（`8c325126-bc83-4c86-8c6e-8759a242928e`）發問
  （見 §6 prompt 樣板）
- NotebookLM 答不出 → 走 web fallback（見 §7）
- 把答案消化、填入每份 .md 的 §6 / §7（不貼原文 raw paste）

### 階段 4 — 收尾（commit 4）
- 完整 `docs/README.md` 總索引（含 4 類目錄、檔名對映、與 linux/windows/aix/ 腳本的連結、`docs/guide/` 取得說明）
- 頂層 `README.md` 在「目錄結構」段加入 `docs/` 描述（中英雙語）
- **刪除 `tmp/` 上層 .txt**（原指令文字已併入各 .md §3 fenced block，是版控起點；新增者循 docs/SOP-TEMPLATE.md）
- 若 `tmp/` 已空則整個刪除目錄

## 6. NotebookLM 驗證 prompt 樣板

每份 SOP 套用：

```
我有一份內部 SOP 叫「<檔名>」，內容如下：

<貼入 .md §1–§5 純文字>

請對照你資料庫裡的 Illumio 25.4 官方文件
（Install_Upgrade Guide、Admin_25_4、PCE 操作手冊、Agent 部署手冊等），回答：

1. 本 SOP 哪些步驟與原廠**完全一致**？引用具體章節 / 頁碼。
2. 哪些步驟是原廠沒有、SOP 自行**補強**？這些補強合理嗎？
3. 哪些步驟與原廠**做法不同**？列差異與可能原因（環境限制 / 版本 / 錯誤）。
4. 哪些**原廠必要步驟** SOP 沒寫到？

請只引用你資料庫裡有的官方文件，不要外推；找不到就明說「資料庫無相關內容」。
```

呼叫方式：`notebooklm ask "<上述 prompt>" -n 8c325126-bc83-4c86-8c6e-8759a242928e --json`

不存 note（避免污染筆記）；回答 parse 後寫入該份 .md 的 §6 / §7。

## 7. Web Fallback 條款（公開 docs）

觸發條件（任一）：
- NotebookLM 回答含「資料庫無」/「無相關」/「找不到」等明確否認
- `references` 為空，或 `cited_text` 與問題語意不符
- 章節 / 頁碼缺失但 SOP 該步驟風險高（如 backup、upgrade）

Fallback 順序：

1. **WebFetch** `https://docs.illumio.com/...` 對應章節（若已知 URL）。
2. **WebSearch** `site:docs.illumio.com <SOP 步驟關鍵字>` → 挑前 2 筆相關 → WebFetch。
3. 仍無 → §7 寫「**原廠文件未涵蓋（NotebookLM + 公開 docs 皆查無）**」。

Web 來源在 §6 標 `[Web]` 並帶 URL；NotebookLM 來源標 `[NotebookLM]` 並帶檔名 + 章節，
讀者能一眼分辨。

## 8. 次要決策（已核准）

| 決策 | 結論 |
|---|---|
| 原 tmp/ 處置 | 階段 4 整個刪除；v0 內容已逐字併入新 .md §3 |
| 跨平台主題 | k8s 放 platform/；憑證放 cert/；不在 linux/windows/aix/ 下重複 |
| 語言 | docs/*.md 主體繁中、技術詞彙保留英文（Pairing Profile, Mode, Activation Key…） |
| VEN install 文件 vs 部署腳本 | docs/ven/install-*.md 寫**手動**程序；自動化用 linux/manual_deploy/* 腳本；雙向連結 |
| commit 訊息 | 英文 conventional commits（沿用現有風格） |
| Web fallback | 觸發條件、順序與標籤見 §7 |

## 9. 風險與緩解

| 風險 | 緩解 |
|---|---|
| NotebookLM 21 次 ask 受 rate limit | 階段 3 串列跑、每次間隔 5s；rate limit 觸發改成等 5 min 重試 |
| SOP 步驟與原廠差太多致 §7 篇幅暴增 | §7 用條列、每點一行；超過 10 點移到附錄 docs/<name>-appendix.md |
| `ilumio FlowLink SOP.txt` 含空白檔名遷移腳本誤判 | 一律用 `mv "<src>" <dst>` 加雙引號；遷移前先 `ls "tmp/<檔名>"` 確認存在 |
| tmp/ 刪除後使用者找不到原文 | 原 .txt 的指令文字在階段 2 已逐字搬入新 .md §3 fenced block；docs/README.md 對映表保留原檔名 → 新檔名雙向查找 |
| NotebookLM context.json 在 parallel session 被覆蓋 | 一律用 `-n 8c325126-bc83-4c86-8c6e-8759a242928e`，不依賴 `notebooklm use` |

## 10. 完成標準（Definition of Done）

- [ ] `docs/` 樹下 21 份 .md 全部存在且通過 §4 七段檢查
- [ ] 每份 .md 的 §6 至少有一筆 `[NotebookLM]` 或 `[Web]` 來源
- [ ] `docs/README.md` 總索引列出 21 份對映 + 與 linux/windows/aix/ 的連結 + `docs/guide/` 取得說明
- [ ] `docs/guide/` 含 2 份原廠 docx（**本機存在但 git 排除**），`.gitkeep` 入庫
- [ ] `.gitignore` 含 `docs/guide/*.docx`，`git status` 不顯示 docx 為 untracked
- [ ] 頂層 `README.md` 提到 `docs/` 並雙語對照
- [ ] `tmp/` 已刪除（或至少所有 .txt 與 guide/ 都已遷移）
- [ ] 4 個 commit 訊息英文、conventional 格式、可逐步 review
- [ ] `git log --oneline -5` 顯示完整 4 階段

## 11. 後續（不在本案）

- 把 `docs/` 接上 GitHub Pages / mkdocs 靜態網站。
- SOP 英文版（針對跨國同事）。
- 從 `linux/manual_deploy/deploy-illumio.sh` 自動 lint 與 docs/ven/install-linux.md 步驟同步。
