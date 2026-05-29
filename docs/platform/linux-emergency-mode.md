> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/linux_emergency_mode_sop.txt`

# Linux Emergency Mode 進入與修復

## 1. 目的與適用情境

處理 Linux 開機失敗並停在 "You are in emergency mode" 畫面的情況，主要原因為檔案系統損毀（fsck failed）或 `/etc/fstab` 掛載設定錯誤，適用於 Illumio PCE 節點或任何 Linux 主機因非正常關機、斷電或 fstab 誤設定導致無法正常開機的緊急修復場景。

## 2. 前置條件

- 能物理或遠端存取伺服器主控台（Console）
- 已知 root 密碼（Emergency mode 需要輸入 root 密碼才能進入 shell）
- （備用）Linux Live USB（若根目錄本身損毀需使用）

## 3. 操作步驟

### 一、前置準備與登入

當畫面出現 "Give root password for maintenance" 時，輸入 root 密碼並按下 Enter 登入。

嘗試簡單修復（非必要，但值得一試）：

```
Ctrl + D  或執行  systemctl default
```

若畫面再次跳回 Emergency mode，繼續執行下列步驟。

### 二、資訊蒐集與診斷

```bash
# 1. 查看系統日誌，尋找紅色或粗體的錯誤訊息
journalctl -xb | less
# (操作：按上下鍵捲動，按 q 離開。尋找關鍵字如 "Failed to mount" 或 "File system check on ... failed")

# 2. 列出所有硬碟與掛載點資訊 (最重要)
lsblk -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT -f
# (說明：確認哪個分割區沒有掛載成功，記下它的「裝置名稱」(如 /dev/sda2) 與「掛載點」(如 /home 或 /))

# 3. 查看目前的開機掛載設定檔
cat /etc/fstab
# (說明：用來比對 UUID 是否與 lsblk 顯示的一致)
```

### 三、判斷故障類型並執行修復

#### 路徑 3A：檔案系統損毀（fsck failed, exit status 4）

**情況 A-1：若壞掉的是根目錄 /**

```bash
# 1. 建立強制掃描標記
touch /forcefsck
# (說明：這是在告訴系統「下次開機時，請自動強制檢查並修復所有硬碟」)

# 2. 重開機
reboot
# (說明：重開機過程會比平常久，請耐心等待系統自動修復)

# 3. 若上述無效 (如開機循環失敗)
# 需使用 Linux Live USB 開機後對該分割區執行：
fsck -f -y /dev/sdXN
```

**情況 A-2：若壞掉的是一般分割區（如 /home, /var, /data）**

```bash
# 1. 確保目標分割區未掛載
umount /dev/sdXN
# (範例：umount /dev/sda2)
# (注意：若顯示 target is busy，可嘗試強制卸載：umount -l /dev/sdXN)

# 2. 執行檔案系統修復 (針對 ext2/ext3/ext4)
fsck -f -y /dev/sdXN
# 或指定類型：e2fsck -f -y /dev/sdXN
# (參數說明：-f 強制檢查，-y 自動回答 yes 修復所有錯誤)

# [特殊情況：XFS 格式]
# 若檔案系統為 xfs (由 lsblk 確認)，請勿使用 fsck，改用：
xfs_repair /dev/sdXN

# 3. 測試掛載
mount -a
# (說明：若無跳出錯誤訊息，代表修復成功)

# 4. 重開機
reboot
```

#### 路徑 3B：設定檔錯誤（Timed out waiting for device, Dependency failed）

```bash
# 1. 重新掛載根目錄為「可讀寫」模式 (關鍵步驟)
mount -o remount,rw /
# (說明：Emergency mode 預設根目錄是唯讀 (Read-only)，不執行此指令無法修改檔案)

# 2. 編輯 fstab 設定檔
vi /etc/fstab
# (操作提示：
#  - 移動游標到錯誤的那一行
#  - 按 i 進入編輯模式
#  - 修改 UUID 或檔案格式
#  - 若需暫時略過該硬碟，可在該行最前面加 # 註解掉
#  - 或者修改參數為：defaults,nofail,x-systemd.device-timeout=5s
#  - 按 Esc 退出編輯模式
#  - 輸入 :wq 儲存並離開)

# 3. 測試設定檔語法
mount -a
# (說明：執行後若無錯誤訊息，表示 fstab 格式正確)

# 4. 重開機
reboot
```

## 4. 驗證

系統成功開機後，執行以下檢查：

```bash
# 1. 檢查是否有服務啟動失敗
systemctl --failed

# 2. 確認磁碟掛載狀況
df -h

# 3. 建議紀錄 (供日後參考)
lsblk -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT -f > /root/partition-map.txt
# (說明：將目前的正確磁碟對應表存檔，下次出錯時可直接比對)
```

附錄：fsck 常見回傳碼：
- 0：無錯誤（No errors）
- 1：檔案系統錯誤已修復（File system errors corrected）
- 2：系統需要重開機（System should be rebooted）
- 4：檔案系統錯誤「未」修復（需手動再跑一次）
- 8：操作錯誤（如裝置不存在或正被掛載中）

## 5. 失敗回滾 / 救援

- — 無 —

若 `touch /forcefsck` + 重開機仍無法修復根目錄損毀，必須使用 Linux Live USB 開機後執行 `fsck -f -y /dev/sdXN`。

## 6. 原廠文件參照

- **原廠文件未涵蓋（NotebookLM + 公開 docs 皆查無）**：Linux Emergency Mode 屬 OS 層故障修復（fsck、fstab 錯誤），Illumio 官方文件不涵蓋此主題
- [Web] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_file_systems/checking-and-repairing-a-file-system_managing-file-systems — RHEL 9 fsck 與 e2fsck 官方參考

## 7. 與原廠差異（若有）

- **原廠文件未涵蓋（NotebookLM + 公開 docs 皆查無）**：此 SOP 為 Illumio PCE 節點宿主 OS 層的緊急修復程序，內容屬 Linux 系統管理標準操作，非 Illumio 特有步驟。Illumio 官方視 OS 層操作為管理員先備知識。
