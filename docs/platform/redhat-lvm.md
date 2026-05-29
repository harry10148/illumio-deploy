> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_Redhat_LVM_SOP.txt`

# RedHat LVM 調整（Illumio PCE 場景）

## 1. 目的與適用情境

在 RHEL/CentOS 上對 Illumio PCE 節點進行 LVM 磁碟管理，涵蓋現況檢查、全新硬碟 LVM 建立、VM 線上擴充（Online Resize）、LVM 刪除與縮減，以及 NFS/SMB 網路掛載設定，適用於 PCE 資料庫分區空間不足或初次磁碟規劃等場景。

## 2. 前置條件

- 具備 root 或 sudo 權限
- （擴充場景）已在 vCenter/Hyper-V 完成硬碟擴容
- （Online Resize）已安裝 `growpart` 工具（`cloud-utils-growpart`）
- （NFS/SMB）已安裝 `nfs-utils` 與 `cifs-utils`

## 3. 操作步驟

### 1. 系統磁碟與 LVM 狀態檢視

```bash
# 1.1 查看所有區塊裝置樹狀圖 (最推薦，可看掛載點與階層)
lsblk

# 1.2 查看實體硬碟分割表詳細資訊
fdisk -l

# 1.3 檢查 LVM 三層結構狀態
pvs         # 查看 Physical Volume (實體卷)
vgs         # 查看 Volume Group (卷群組) 剩餘空間
lvs         # 查看 Logical Volume (邏輯卷) 大小與路徑

# 1.4 查看已掛載的磁碟空間與檔案系統類型 (XFS/EXT4)
df -hT

# 1.5 查詢磁碟 UUID (設定 fstab 時強烈建議使用)
blkid
```

### 2. 全新硬碟 LVM 建立流程

場景：插上一顆全新硬碟 `/dev/sdb`，建立 LVM 並掛載至 `/data`：

```bash
# 2.1 初始化 PV (將整顆硬碟轉為實體卷)
pvcreate /dev/sdb

# 2.2 建立 VG (建立卷群組，名稱自訂，如 vg_data)
vgcreate vg_data /dev/sdb

# 2.3 建立 LV (建立邏輯卷，名稱自訂，如 lv_project)
# 方式 A: 使用 100% 剩餘空間 (最常用)
lvcreate -n lv_project -l 100%FREE vg_data
# 方式 B: 指定固定大小 (如 50G)
lvcreate -n lv_project -L 50G vg_data

# 2.4 格式化檔案系統
# RHEL 7/8/9 預設推薦 XFS (效能好，但無法縮小)
mkfs.xfs /dev/vg_data/lv_project
# 若有縮小需求請用 EXT4
# mkfs.ext4 /dev/vg_data/lv_project

# 2.5 建立掛載點並測試掛載
mkdir -p /data
mount /dev/vg_data/lv_project /data
df -hT /data

# 2.6 設定開機自動掛載 (編輯 /etc/fstab)
# 步驟 A: 查詢 UUID
blkid /dev/vg_data/lv_project
# (假設 UUID="1234-5678-abcd-efgh")

# 步驟 B: 編輯檔案
vi /etc/fstab

# 步驟 C: 在檔案末端加入以下內容 (依格式選擇)：
# [UUID]                         [掛載點] [類型]  [參數]    [備份] [檢測]
UUID=1234-5678-abcd-efgh         /data    xfs    defaults  0      0

# 步驟 D: 驗證設定 (極重要，若報錯請勿重開機)
mount -a
# 若無錯誤訊息，代表設定成功
```

### 3. VM 虛擬機硬碟擴充流程（Online Resize）

場景：VM 空間不足，已在 vCenter/Hyper-V 將硬碟 `/dev/sdb` 從 50G 調整為 100G，不增加新硬碟、不重開機，直接擴容 LVM。

```bash
# 前提：需安裝 growpart 工具
dnf install cloud-utils-growpart -y  (或 yum install)

# 3.1 重新掃描 SCSI Bus (讓 OS 識別硬碟變大)
# 將 'sdb' 替換為實際硬碟代號
echo 1 > /sys/class/block/sdb/device/rescan
# 檢查是否變大 (disk 變大，但 part/lvm 尚未變)
lsblk

# 3.2 擴充實體分割區 (Partition)
# 語法: growpart <硬碟> <分割區號碼> (注意空格)
# 若 PV 建立在 /dev/sdb1
growpart /dev/sdb 1

# 3.3 通知 LVM 實體卷空間已改變 (PV Resize)
pvresize /dev/sdb1
# 驗證 (VSize 應變大，VFree 增加)
pvs

# 3.4 擴充邏輯卷與檔案系統 (LV Extend)
# -r 參數會自動執行 resize2fs 或 xfs_growfs
lvextend -r -l +100%FREE /dev/vg_data/lv_project

# 3.5 最終檢查
df -hT /data
```

### 4. LVM 刪除與縮減

**4.1 刪除 LVM（資料將遺失）：**

```bash
1. 卸載磁區： umount /data
2. 移除設定： vi /etc/fstab (刪除對應行，否則開機會失敗)
3. 刪除 LV ： lvremove /dev/vg_data/lv_project
4. 刪除 VG ： vgremove vg_data
5. 刪除 PV ： pvremove /dev/sdb
```

**4.2 縮減 LVM（僅限 EXT4，XFS 不支援縮小）：**

警告：操作前強烈建議備份，縮小有資料遺失風險。

```bash
1. 卸載：
   umount /data
2. 強制檢查磁碟：
   e2fsck -f /dev/vg_data/lv_project
3. 縮小檔案系統 (範例：縮到 10G)：
   resize2fs /dev/vg_data/lv_project 10G
4. 縮小 LV (必須 >= 檔案系統大小)：
   lvreduce -L 10G /dev/vg_data/lv_project
5. 重新掛載：
   mount /data
```

### 5. NFS 與 SMB/CIFS 掛載設定

```bash
# 安裝必要套件：
dnf install nfs-utils cifs-utils -y
```

**5.1 NFS Client 掛載（假設 Server: 192.168.1.100, Path: /srv/nfs_share）：**

```bash
# 1. 測試掛載：
mount -t nfs 192.168.1.100:/srv/nfs_share /mnt/nfs_data

# 2. 開機自動掛載 (/etc/fstab)：
# 關鍵參數: _netdev (等待網路啟動後再掛載)
192.168.1.100:/srv/nfs_share  /mnt/nfs_data  nfs  defaults,_netdev  0 0
```

**5.2 SMB/CIFS 掛載（假設 Server: 192.168.1.200, Share: win_share）：**

```bash
# 1. 建立帳號密碼檔 (避免明碼寫在 fstab)：
vi /root/.smbcreds
# -----------------------
# username=winuser
# password=MySecretPass
# domain=WORKGROUP
# -----------------------
chmod 600 /root/.smbcreds

# 2. 測試掛載：
mount -t cifs -o credentials=/root/.smbcreds //192.168.1.200/win_share /mnt/smb_data

# 3. 開機自動掛載 (/etc/fstab)：
//192.168.1.200/win_share	/mnt/smb_data	cifs	credentials=/root/.smbcreds,_netdev,vers=3.0  0 0
# 註: 若掛載失敗，可嘗試更改 vers=2.0 或 1.0
```

## 4. 驗證

```bash
# 確認擴充後空間
df -hT /data

# 確認 LVM 狀態
pvs && vgs && lvs

# 確認 fstab 語法正確
mount -a
```

## 5. 失敗回滾 / 救援

常見問題：

- **lvextend 成功但 df -h 空間沒變？** 忘了調整檔案系統大小。
  - XFS：`xfs_growfs /data`
  - EXT4：`resize2fs /dev/vg_data/lv_project`

- **無法卸載（target is busy）？** 有程式正在使用該目錄。
  - `fuser -m /data`（查看 PID）或 `lsof /data`

- **開機進入 Emergency Mode？** 通常是 `/etc/fstab` 寫錯（UUID 錯誤或語法錯誤）。
  - 解法：輸入 root 密碼 → `mount -o remount,rw /` → 修正 fstab → 重開機

## 6. 原廠文件參照

- **原廠文件未涵蓋（NotebookLM + 公開 docs 皆查無）**：LVM 磁碟管理屬 OS 層操作，Illumio 官方文件不涵蓋此主題
- [Web] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_logical_volumes/index — RHEL 9 LVM 官方管理指南

## 7. 與原廠差異（若有）

- **原廠文件未涵蓋（NotebookLM + 公開 docs 皆查無）**：此 SOP 為 Illumio PCE 節點宿主 OS 的 LVM 磁碟管理程序，屬 RHEL 系統管理標準操作。Illumio 官方文件（Admin_25_4 §traffic_datastore > data_dir、max_disk_usage_gb）僅說明 PCE 流量資料庫的儲存路徑設定，不涉及 LVM 操作本身。
