> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/pce_remove_ndoe.txt`

# Illumio PCE 節點移除

## 1. 目的與適用情境

從 Illumio PCE SNC 的 Consul 叢集健康狀態中移除殘留的 Loopback（127.0.0.1）節點紀錄，適用於 POC 環境或測試環境中出現幽靈節點導致 cluster health 異常的情境；執行前須確認非生產環境且已完成本地政策資料庫備份。

## 2. 前置條件

- 非生產環境（此程序僅適用於 POC 或 SNC 測試環境）
- 已完成本地政策資料庫備份
- 具備 root 或 PCE 服務帳號權限

## 3. 操作步驟

### 方法一（推薦）：illumio-pce-ctl cluster-leave

原廠標準路徑，適用大多數情境。在被移除節點上以 root 執行：

```bash
sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl cluster-leave
# 等待節點完成離開流程，cluster status 會自動更新
sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl cluster-status -w
```

### 方法二（troubleshooting）：Ruby ConsulClient 直接清除 Consul 紀錄

> ⚠️ **僅用於故障情境**：方法一執行失敗或節點已不可達時的緊急清除方式。不應作為日常移除節點的標準流程。

先確認 `persistent_data` 位置及叢集伺服器清單：

```bash
cat /etc/illumio-pce/runtime_env.yml | grep persistent
cat /var/lib/illumio-pce/data/illumio/cluster_servers
```

載入 PCE Ruby 支援腳本並查詢叢集健康狀態（輸出至日誌）：

```bash
source /opt/illumio-pce/illumio/scripts/support
ruby -e "require 'illumio/consul_client'; cc = Illumio::ConsulClient.new; puts cc.get_val('cluster_health_data')" >> cluster_health_data.log
```

若發現 127.0.0.1，執行以下命令移除（若移除成功，將會顯示 "true" 為結果）：

```bash
ruby -e "require 'illumio/consul_client'; puts Illumio::ConsulClient.new.delete_key('node_health_data/127.0.0.1')"
```

再次確認叢集健康狀態：

```bash
source /opt/illumio-pce/illumio/scripts/support
ruby -e "require 'illumio/consul_client'; cc = Illumio::ConsulClient.new; puts cc.get_val('cluster_health_data')" >> cluster_health_data.log
```

## 4. 驗證

確認 `cluster_health_data.log` 中不再出現 `127.0.0.1` 的節點紀錄，且 `delete_key` 指令回傳 `true`。

## 5. 失敗回滾 / 救援

- — 無 —

若操作後叢集狀態異常，可從先前備份的政策資料庫進行還原。

## 6. 原廠文件參照

- [NotebookLM] Core 25.4 Administration §Manage PCE Cluster — 原廠正式移除節點方式為 illumio-pce-ctl cluster-leave（在 runlevel 1 下執行），非 Ruby ConsulClient 腳本
- [NotebookLM] Illumio_PCE操作手冊_20251128.pdf — 資料庫無此 Ruby ConsulClient 腳本的相關內容

## 7. 與原廠差異（若有）

- §3 已重整：方法一補入原廠標準 `cluster-leave` 流程；既有 Ruby ConsulClient 方式降級為方法二「故障情境」備援（2026-05-29 編輯回合）。
