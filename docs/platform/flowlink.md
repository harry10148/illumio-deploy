> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/ilumio FlowLink SOP.txt`

# Illumio FlowLink SOP

## 1. 目的與適用情境

維運 Illumio FlowLink 日誌轉發系統，涵蓋系統架構確認、關鍵目錄說明、Crontab 自動排程邏輯、日常健康檢查步驟，以及各種故障情境的重啟程序，適用於 FlowLink + Syslog Relay 的日常維運與障礙排除。

## 2. 前置條件

- FlowLink 與 Syslog Relay 已安裝於 `/opt/flowlink/`
- 具備 root 或 sudo 權限
- 確認系統架構：Forcepoint → Syslog Relay（UDP 514 → UDP 5514）→ FlowLink → SaaS（TCP 443）

## 3. 操作步驟

### 系統架構與流量路徑

流量方向：
Forcepoint (來源) → Syslog Relay (清洗) → FlowLink (主程式) → SaaS (雲端)

通訊埠口對應：
[ Forcepoint ] --(UDP 514)--> [ Syslog Relay ] --(UDP 5514)--> [ FlowLink ]

- Syslog Relay (Python)：負責中文編碼清洗、時間單位轉換、表頭補全。
- FlowLink (Go)：負責將資料加密轉送至 SaaS (TCP 443)。

### 關鍵目錄與檔案說明

目錄位置：`/opt/flowlink/`

- `api_info`：連線至 SaaS 使用的 API KEY（敏感資料，請勿刪除）
- `config-syslog.yml`：FlowLink 主程式設定檔
- `syslog_relay.py`：中文清洗程式（Python 腳本）
- `monitor_services.sh`：自動監控腳本（Crontab 定期執行）
- `data/`：存放暫存資料與 Log

### 自動化排程（Crontab）

本系統已設定自動維護，管理員無需手動執行，但需知曉其邏輯。

```
# (1) 核心監控 (每 30 分鐘)
*/30 * * * * /opt/flowlink/monitor_services.sh >> /var/log/flowlink_monitor.log 2>&1

# (2) 清理備份 (每天 03:00)
0 3 * * * find /var/log/flowlink_crash_backups -name "*.log" -type f -mtime +7 -delete

# (3) 應用程式 Log 清空 (每天 03:00)
0 3 * * * truncate -s 0 /opt/flowlink/data/flowlink.log

# (4) 監控日誌輪替 (每週日 04:00)
0 4 * * 0 mv /var/log/flowlink_monitor.log /var/log/flowlink_monitor.log.old; echo "Log Rotated" > /var/log/flowlink_monitor.log
```

### 日常健康檢查

步驟 A：使用腳本快速檢查（推薦）：

```bash
/opt/flowlink/monitor_services.sh
```

正常輸出：

```
[OK] FlowLink is running.
[OK] Syslog Relay is running.
```

步驟 B：檢查 Port 監聽狀態：

```bash
netstat -uapnl | grep -E '514|5514'
```

檢查重點：
- UDP 514 必須被 python3 佔用
- UDP 5514 必須被 flowlink 佔用

步驟 C：檢查 FlowLink 運作日誌：

```bash
tail -f /opt/flowlink/data/flowlink.log
```

觀察：確認 "1-min rate" 數值大於 0，代表有流量進出。

### 故障排除與服務重啟

情境一：修改 FlowLink 設定檔後重啟：

```bash
# 1. 停止服務:
illumio-flowlink-ctl stop
# 2. 指定設定檔啟動:
illumio-flowlink-ctl start --config /opt/flowlink/config-syslog.yml
```

情境二：重啟 Syslog Relay（UDP 514 Port 消失或中文解析異常時）：

```bash
# 1. 重啟服務:
systemctl restart syslog-relay
# 2. 確認狀態:
systemctl status syslog-relay
```

情境三：查看自動重啟紀錄：

```bash
cat /var/log/flowlink_monitor.log
```

或手動執行監控腳本：

```bash
/opt/flowlink/monitor_services.sh
```

## 4. 驗證

```bash
# 確認兩個服務正常
/opt/flowlink/monitor_services.sh

# 確認 Port 監聽
netstat -uapnl | grep -E '514|5514'
```

## 5. 失敗回滾 / 救援

- — 無 —

若服務重啟後仍異常，查閱 `/var/log/flowlink_monitor.log` 與 `/opt/flowlink/data/flowlink.log` 確認錯誤原因。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §FlowLink — FlowLink 功能說明：正規化與聚合網路流量資料後送往 PCE，支援 netflow/ipfix/sflow/aws/text/syslog 格式
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §FlowLink — illumio-flowlink-ctl start --config <path> / stop / status 指令
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §FlowLink — config-syslog.yml 設定檔結構：pce_addr、api_key、data_directory、aggregation_minutes、destinations（parser/connectors/properties）

## 7. 與原廠差異（若有）

- **Syslog Relay 中介層**：SOP 在 FlowLink 前加入自製 Python Syslog Relay（負責中文編碼清洗、時間轉換、表頭補全）；原廠 FlowLink 支援直接接收 syslog（Text parser + UDP/TCP connector），Syslog Relay 為環境特定補強（處理 Forcepoint 中文格式問題），非原廠架構。
- **illumio-flowlink-ctl 指令**：SOP 的 start/stop 指令與原廠（Install_Upgrade §FlowLink）一致；SOP 使用 --config 指定設定檔路徑，與原廠一致。
- **Crontab 監控腳本**：原廠未提供此類自動重啟邏輯，SOP 補強合理。
