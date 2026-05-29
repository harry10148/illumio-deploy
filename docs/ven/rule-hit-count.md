> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_rulehitcount.txt`

# Illumio Rule Hit Count（規則命中計數查詢）

## 1. 目的與適用情境

透過 Illumio PCE REST API 啟用 Rule Hit Count 功能，並設定規則命中計數報告範本為啟用狀態，適用於需要統計各防火牆規則實際命中次數以進行規則審查或優化的場景。

## 2. 前置條件

- 具備 PCE API Key 及 Key Secret（需有組織管理員權限）
- `curl` 已安裝且可連線至 PCE
- 已知 PCE 伺服器位址（含 Port）及 Org ID

## 3. 操作步驟

設定環境變數：

```bash
ILO_API_KEY_ID="<ILO_API_KEY_ID>"
ILO_API_KEY_SECRET="<ILO_API_KEY_SECRET>"
ILO_SERVER="pce.lab.local:8443"
ILO_ORG_ID="1"
```

啟用 Rule Hit Count（修改草稿防火牆設定）：

```bash
curl -i -X PUT https://${ILO_SERVER}/api/v2/orgs/${ILO_ORG_ID}/sec_policy/draft/firewall_settings -H "Content-Type:application/json" -u ${ILO_API_KEY_ID}:${ILO_API_KEY_SECRET} -d '{"rule_hit_count_enabled_scopes": [[]]}'
```

提交政策變更（將草稿變更佈署至 Active）：

```bash
curl -i -X POST https://${ILO_SERVER}/api/v2/orgs/${ILO_ORG_ID}/sec_policy -H "Content-Type: application/json" -u ${ILO_API_KEY_ID}:${ILO_API_KEY_SECRET} -d '{"update_description":"Enable rule hit count","change_subset": {"firewall_settings":[{"href":"/orgs/ILO_ORG_ID/sec_policy/draft/firewall_settings"}]}}'
```

啟用 Rule Hit Count 報告範本：

```bash
curl -i -X PUT https://${ILO_SERVER}/api/v2/orgs/${ILO_ORG_ID}/report_templates/rule_hit_count_report -H "Content-Type: application/json" -u ${ILO_API_KEY_ID}:${ILO_API_KEY_SECRET} -d '{"enabled": true}'
```

## 4. 驗證

確認以上 API 呼叫均回傳 HTTP 200 或 204，並在 PCE Web UI 的 Reports 頁面確認 Rule Hit Count 報告已顯示。

## 5. 失敗回滾 / 救援

- — 無 —

若 API 回傳錯誤，確認 API Key 權限等級（需組織管理員）及 Org ID 設定是否正確。

## 6. 原廠文件參照

- [NotebookLM] REST APIs 25.4 §Rule Hit Count — PUT /api/v2/orgs/:xorg_id/sec_policy/draft/firewall_settings，payload {"rule_hit_count_enabled_scopes": [[]]} 啟用全域；啟用後須提交 DRAFT 政策
- [NotebookLM] REST APIs 25.4 §Rule Hit Count — PUT /api/v2/orgs/:xorg_id/report_templates/rule_hit_count_report，payload {"enabled": true} 啟用報告範本
- [NotebookLM] Admin 25.4 §Showing Rule ID in Syslog — Rule Hit Count 預設為停用，啟用後可在 UI Settings > Event Settings > Event Forwarding 設定 Syslog 轉發

## 7. 與原廠差異（若有）

- 主要流程與原廠 REST APIs 25.4 一致；但 SOP 缺少「POST sec_policy 後於 VEN 端確認 Rule Hit Count 生效」的驗證步驟（原廠流程要求此步驟）。
- SOP 的 PUT firewall_settings（rule_hit_count_enabled_scopes）與 PUT report_templates/rule_hit_count_report 兩個 API 呼叫均與原廠（REST APIs 25.4 §Rule Hit Count）相符。
