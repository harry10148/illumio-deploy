> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_ven_aix_uninstall.txt`

# Illumio VEN — AIX 解除安裝

## 1. 目的與適用情境

在 IBM AIX 主機上完整解除安裝 Illumio VEN，以標準 `unpair` 流程為主（含 PCE 登出、防火牆還原、套件移除），並選擇性移除 IPFilter；亦包含 `unpair` 無法執行時的手動替代移除步驟。

## 2. 前置條件

- IBM AIX 系統，具備 root 權限
- VEN 目前已安裝且 `illumio-ven-ctl` 可執行
- （建議）確認移除前防火牆策略的還原方式（recommended / open / saved）
- 複製指令時，確保減號為標準 ASCII「-」，避免全形符號「–」導致執行失敗

## 3. 操作步驟

### 第 1 章：檢查已安裝項目

```bash
lslpp -L | egrep -i 'illu|ipf'
```

### 第 2 章：標準卸載程序（使用 Unpair）

```bash
# 1. 執行前，先確認 VEN 目前的運行狀態
/opt/illumio_ven/illumio-ven-ctl status

# 2. 執行 Unpair 進行完整卸載 (預設建議使用 recommended 參數)
/opt/illumio_ven/illumio-ven-ctl unpair recommended
```

`unpair` 參數說明：
- `recommended`：卸載後暫時封鎖多數連線，僅允許 SSH（Port 22），直到系統重新啟動（官方建議值）。
- `open`：卸載後完全清空防火牆規則。
- `saved`：卸載並嘗試還原至首次安裝 VEN 前的防火牆狀態（注意：舊設定可能已不符現況，可能導致網路中斷）。

### 第 3 章：移除 IPFilter（視需求執行）

```bash
# 移除 IPFilter 主程式
# 1. 停用目前的過濾規則 (若指令存在)
ipf -D

# 2. 移除套件本體
installp -u ipfl.rte
```

清理文件包：

```bash
# 1. 再次檢查剩餘的 IPFilter 相關套件 (預期可能只剩說明文件 ipfl.man.en_US)
lslpp -L | egrep -i 'illu|ipf'

# 2. 若需清空，可連同文件包一起移除
installp -u ipfl.man.en_US
```

### 第 4 章：後續驗證與清理

```bash
lslpp -L | egrep -i 'illu|ipf'
```

預期輸出結果應為空白，代表 `illumio-ven` 與 `ipfl.rte`（及說明文件）均已從系統中移除。

### 附錄：例外狀況處理（手動套件移除）

僅當 `illumio-ven-ctl unpair` 腳本損壞或無法執行時使用。注意：使用此方式移除後，PCE 中控台會保留該設備的「離線（Offline）」紀錄，需至介面手動刪除，且系統中會殘留日誌與快取目錄。

```bash
# 1. 停止背景程序
ps -ef | grep illumio
kill -9 <PID>

# 2. 透過 AIX 原生套件管理移除軟體
installp -u illumio-ven

# 3. 手動刪除殘留的目錄與資料
rm -rf /opt/illumio_ven
rm -rf /opt/illumio_ven_data
```

## 4. 驗證

```bash
lslpp -L | egrep -i 'illu|ipf'
```

輸出結果應為空白，代表卸載完成。

## 5. 失敗回滾 / 救援

- — 無 —

若 `unpair` 執行失敗，使用附錄中的手動移除步驟，並於完成後在 PCE Web UI 中手動刪除殘留的 Offline 設備紀錄。

## 6. 原廠文件參照

- [NotebookLM] Illumio Agent部署手冊_20250815.pdf §6.3 解除安裝(Uninstall) / §7.2 AIX 查核清單 — illumio-ven-ctl unpair [recommended|saved|open] 為標準卸載流程
- [NotebookLM] Admin 25.4 / Install_Upgrade_Admin_25_4 §Deactivate and Unpair VENs > Unpair Using System Commands — unpair 參數說明，以及 installp -u illumio-ven 替代方式
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §AIX: Install and Upgrade — 移除 IPFilter 必須在 VEN 移除**之後**執行；先移除 IPFilter 會導致 VEN 卸載前驗證失敗

## 7. 與原廠差異（若有）

- **IPFilter 移除順序**：SOP §3 先執行 ipf -D 再 installp -u ipfl.rte，此為 VEN 已移除後的操作，順序正確；原廠明確警告不可在 VEN 移除前先移除 IPFilter，SOP 結構上正確。
- **unpair 參數說明**：SOP 詳細說明 recommended/open/saved 三種參數，與原廠（Agent部署手冊 §6.3）一致。
- **手動移除例外步驟**：SOP 附錄（kill -9 + installp -u + rm -rf）屬 unpair 無法執行時的緊急替代方式，原廠文件亦收錄 installp -u illumio-ven 路徑，SOP 補充合理。
