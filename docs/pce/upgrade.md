> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_pce_upgrade_snc.txt`

# Illumio PCE SNC 升級程序

## 1. 目的與適用情境

對運行中的 Illumio PCE SNC（或 MNC）執行版本升級，包含升級前備份、停止服務、安裝新版 RPM、資料庫 migration 及恢復完整服務，並附有升級失敗時的完整回滾程序。

## 2. 前置條件

- 確認目前 PCE 運作正常，可執行 `cluster-status`
- 新版 RPM 檔案（PCE 主程式與 UI）已備妥於本機
- 已確認執行 DB dump 的節點（`agent_traffic_redis_server` 所在節點）
- 有足夠磁碟空間存放備份檔案
- 已備份 `/etc/illumio-pce/runtime_env.yml`

## 3. 操作步驟

確認叢集狀態，找出 `agent_traffic_redis_server` 所在節點（從該節點執行 dump）：

```bash
sudo -u ilo-pce illumio-pce-ctl cluster-status
```

備份設定檔與資料庫（從 `agent_traffic_redis_server` 節點執行）：

```bash
sudo -u ilo-pce illumio-pce-db-management dump --file /tmp/ilo-db-bak
sudo -u ilo-pce illumio-pce-db-management traffic dump --file /tmp/ilo-traffic-bak
```

停止 PCE 服務：

```bash
sudo -u ilo-pce illumio-pce-ctl stop --wait
sudo -u ilo-pce illumio-pce-ctl status -sv --wait
```

安裝新版 RPM（core node/SNC 安裝主程式 + UI；data node 僅安裝主程式）：

```bash
# core node / SNC
rpm -Uvh illumio_pce_rpm illumio_ui_rpm

# data node
rpm -Uvh illumio_pce_rpm
```

安裝範例（實際版本號請依現場替換）：

```bash
rpm -Uvh illumio-pce-25.2.11-10.el9.x86_64.rpm illumio-pce-ui-25.2.11.UI1-2.x86_64.rpm
```

環境預檢：

```bash
sudo -u ilo-pce illumio-pce-ctl check-env
```

啟動至 Runlevel 1 並執行資料庫 migration：

```bash
sudo -u ilo-pce illumio-pce-ctl start --runlevel 1
sudo -u ilo-pce illumio-pce-ctl status -sv --wait
sudo -u ilo-pce illumio-pce-db-management migrate
```

提升至 Runlevel 5（完整服務）：

```bash
sudo -u ilo-pce illumio-pce-ctl set-runlevel 5
sudo -u ilo-pce illumio-pce-ctl status -sv --wait
```

上傳新版 VEN bundle（含相容性矩陣）：

```bash
sudo -u ilo-pce illumio-pce-ctl ven-software-install /tmp/illumio-ven-bundle-25.2.10-1004.tar.bz2 --compatibility-matrix /tmp/illumio-release-compatibility-71-442.tar.bz2
```

VEN bundle 管理指令：

```bash
sudo -u ilo-pce illumio-pce-ctl compatibility-matrix-install matrix_file_path
sudo -u ilo-pce illumio-pce-ctl ven-software-install bundle_path

sudo -u ilo-pce illumio-pce-ctl ven-software-releases-list
sudo -u ilo-pce illumio-pce-ctl ven-software-release-set-default release
sudo -u ilo-pce illumio-pce-ctl ven-software-release-delete release
```

## 4. 驗證

```bash
# 確認叢集狀態，所有服務應呈現 RUNNING
sudo -u ilo-pce illumio-pce-ctl status -sv --wait
```

## 5. 失敗回滾 / 救援

若升級後發生異常，執行以下回滾程序：

```bash
#restore 指令
sudo -u ilo-pce illumio-pce-ctl stop
sudo -u ilo-pce illumio-pce-ctl start --runlevel 1
sudo -u ilo-pce illumio-pce-ctl cluster-status -w
sudo -u ilo-pce illumio-pce-db-management restore --file /mnt/smb/ilo-db-bak-xxxxxxxx.dump
sudo -u ilo-pce illumio-pce-db-management traffic restore --file /mnt/smb/ilo-traffic-bak-xxxxxxxx.dump
sudo -u ilo-pce illumio-pce-db-management migrate
sudo -u ilo-pce illumio-pce-ctl set-runlevel 5
sudo -u ilo-pce illumio-pce-ctl listen-only-mode disable
```

## 6. 原廠文件參照

- [NotebookLM] Core 25.4 Administration §PCE Database Backup > When to Back Up — 明確要求升級前後執行 dump + traffic dump，runtime_env.yml 需手動另行備份
- [NotebookLM] Core 25.4 Administration §Database Migration, Failover, and Restore > Migrate PCE Databases — 升級後必須在 runlevel 1 下執行 db-management migrate，再 set-runlevel 5
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Set Up PCE for VEN Installation > Upload the VEN Upgrade Compatibility Matrix — 相容性矩陣必須先於 VEN bundle 上傳（ven-software-install --compatibility-matrix 參數）
- [NotebookLM] Core 25.4 Administration §PCE Control Interface — illumio-pce-env check 用於驗證 runtime_env.yml 語法

## 7. 與原廠差異（若有）

- **RPM 升級指令**：原廠 Install_Upgrade Guide 25.4 未收錄 PCE RPM 升級指令（僅有 VEN RPM）；SOP 的 rpm -Uvh 指令基於 25.2.x 指南，仍適用。
- **backup 步驟**：SOP 升級前備份 dump + traffic dump 與原廠一致；原廠額外強調 runtime_env.yml 需手動備份，SOP 已涵蓋。
- **db-management migrate**：SOP 包含 migrate 步驟，與原廠要求一致。
- **check-env 步驟**：SOP 使用 illumio-pce-ctl check-env，原廠文件記錄 illumio-pce-env check（功能相近但指令名稱不同），建議確認版本對應。
