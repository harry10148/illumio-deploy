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
