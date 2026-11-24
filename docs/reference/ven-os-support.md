# VEN 作業系統支援與相依套件

> **資料來源**：Illumio Support Portal（Server VEN 26.2.21、Endpoint VEN 26.2.20，對應 PCE 26.2.20 / 26.40）  
> **擷取日期**：2026-11-24

原廠的支援表會隨版本更新。部署其他版本的 VEN 時，以原廠頁面為準：

- Server VEN：<https://support.illumio.com/shared/software/os-support-package-dependencies/ven.html>
- Endpoint VEN：<https://support.illumio.com/shared/software/os-support-package-dependencies/endpoint.html>

## 使用這份表之前

- 原廠要求在安裝 VEN **之前**先裝好所有相依套件。表中沒有標版本的套件，用作業系統發行版內附的版本。
- 支援表與安裝包實際宣告的相依套件不完全相同。以 VEN 26.2.20 實測：
  - RHEL 8 的安裝包沒有宣告 `gmp`、`libcap`、`net-tools`，但宣告了支援表沒列的 `iproute`。
  - Ubuntu 24.04 的安裝包沒有宣告 `net-tools`、`ipset`、`libmnl0`，但宣告了 `ca-certificates`、`iproute2`、`nftables`、`diffutils`、`tar`、`gzip`、`mawk`、`debconf`。
  - 沒有安裝 `net-tools` 的 Ubuntu 24.04 主機，VEN 26.2.20 運作正常。
- 因此本專案的部署腳本以安裝包試裝的結果決定能不能裝，支援表的差異只提醒。保守的做法是兩邊的套件都裝。
- 查詢某個安裝包實際宣告的相依套件：

  ```bash
  rpm -qpR illumio-ven-<VERSION>.<PLATFORM>.rpm
  dpkg-deb -f illumio-ven-<VERSION>.<PLATFORM>.deb Pre-Depends Depends
  ```

## Server VEN：Linux

| 作業系統 | 版本 | 相依套件 | 安裝包 |
|---|---|---|---|
| RHEL、CentOS、Oracle Linux（Red Hat kernel） | 5.5 以上 | shadow-utils、tar、sed、gawk、openssl、curl、iptables、net-tools、iptables-ipv6、libcap、gmp、bind-utils、diffutils、gzip | `c5`（i686、x86_64） |
| 同上 | 6.2 以上 | bind-utils、curl、gmp、ipset ≥ 6.11-4、iptables ≥ 1.4.7-16、libcap、libmnl、libnfnetlink、net-tools、sed | `c6`（i686、x86_64） |
| 同上 | 7.0 以上 | 同 6.2 以上。防火牆：iptables | `c7`（x86_64、ppc64le、s390x） |
| RHEL、CentOS、CentOS Stream、Rocky、AlmaLinux、Oracle Linux（Red Hat kernel） | 8.0 以上 | bind-utils、diffutils、curl、gawk、gmp、gzip、libcap、libnfnetlink、net-tools、nftables、sed、shadow-utils、tar、util-linux。防火牆：nftables | `c8`（x86_64、ppc64le、s390x） |
| RHEL、CentOS Stream、Rocky、AlmaLinux、Oracle Linux、Cloud Linux | 9.0 以上、10.0 以上（10 沿用 el9） | 同 8.0 以上 | `el9`（x86_64、ppc64le、s390x、aarch64） |
| Oracle Linux（UEK kernel） | 5.8 以上 | bind-utils（可用 bind97-utils）、curl、iptables、iptables-ipv6、libcap、gmp、sed | `c5` |
| 同上 | 6.2 以上、7.0 以上 | 同 RHEL 6.2 以上 | `c6`、`c7`（7.9 UEK 另有 aarch64） |
| 同上 | 8.0 以上、9.0 以上 | 同 RHEL 8.0 以上 | `c8`（8.6 UEK 另有 aarch64）、`c9` |
| Amazon Linux | AMI 2016.03～2018.03 | bind-utils、curl、gmp、libcap、libnfnetlink、ipset、net-tools、sed | `c6` |
| 同上 | 2 | 同上 | `c7` |
| 同上 | 2023 | 同上 | `c9`（x86_64、aarch64） |
| Ubuntu | LTS 12.04 以上、非 LTS 20.10 以上 | curl、dnsutils、sed、ipset、libcap2、libgmp10、libmnl0、libnfnetlink0、net-tools、uuid-runtime | `u12`、`u14`、`u16`（i386、amd64）；較新版本由 PCE 提供 `u22`、`u24` 等 |
| Debian | 7、12、13 | apt-transport-https、curl、dnsutils、libcap2、libgmp10、libmnl0、libnfnetlink0、ipset、net-tools、sed、uuid-runtime | `d7`（i386、amd64） |
| SUSE Linux Enterprise Server | 11 SP3 以上 | bind-utils、curl、sed、gmp、ipset、iptables、libcap2、libmnl0、libnfnetlink0、net-tools、openssl-certs | `s11`（x86_64、ppc64、s390x） |
| 同上 | 12 GA、12 SP1 以上 | SLES 11 的清單，另加 net-tools-deprecated | `s12`（x86_64、ppc64le、s390x） |
| 同上 | 15 GA、15 SP1 以上、16 以上 | SLES 12 的清單，另加 libipset、sysvinit-tools | `s12` |

補充說明：

- **套件名稱對應**：支援表的 `dnsutils` 在 Ubuntu 20.04 以上與 Debian 12 以上實際是 `bind9-dnsutils`；`gmp` 在 Debian 系與 SLES 12 以上是 `libgmp10`；`openssl-certs` 在 SLES 12 以上是 `ca-certificates-mozilla`；`libipset` 在 SLES 15 是 `libipset13`。SLES 的實際名稱依 Service Pack 而異，先用 `zypper search` 確認。
- **apt-transport-https**：原廠註明這是「與 Debian 套件庫配對」時才需要。apt 1.5 起已內建 HTTPS，Debian 12 以上不需另外安裝。
- **Ubuntu 18.04**：使用 16.04（Xenial）的安裝包。
- **Debian 10**：不支援 SecureConnect。
- **SUSE 11**：原廠建議核心版本 3.0.101-0.47.71。
- **本專案腳本的支援範圍**：RHEL 系（含 `ID_LIKE` 為 rhel 的發行版）與 Debian 系。SLES 與 Amazon Linux 沒有測試過，請用官方配對指令或全手動安裝。

## Server VEN：Windows

| 類別 | 版本 |
|---|---|
| Windows Server | 2025、2022、2019、2016（含 Core 1607）、2012 R2、2012、2008 R2 SP1；半年通道 1803、1809、1903、1909、20H2 |
| Windows 用戶端 | 11、10（1511 LTSB 至 22H2）、8.1、7 |

- 安裝包：`illumio-ven.win.x64.exe`、`illumio-ven.win.x86.exe`。
- 安裝前先套用最新的 Service Pack。
- Windows Server 2008 R2 SP1 與 Windows 7 只支援到 TLS 1.1。
- Windows 7 與 10 在 Server VEN 上的設定有限，建議用於 VDI 等以有線介面為主的環境；無線與 VPN 介面的政策強制由 Endpoint VEN 支援。

## Server VEN：AIX 與 Solaris

| 作業系統 | 版本 | 需求與限制 | 安裝包 |
|---|---|---|---|
| AIX | 6.1 TL9；7.1、7.2、7.3 TL0 以上 | 支援 LPAR，不支援 WPAR；不支援原生 IPSec 與 SecureConnect；僅支援 IBM POWER | `illumio-ven.bff` |
| Solaris（x86 64 位元、SPARC 64 位元） | 10 U8 以上、11.1 以上 | Solaris 10 需要 SUNWbash、SUNWxcu4；Solaris 11 需要 shell/bash、system/xopen/xcu4。支援實體機、LDOM、Zones 與 Exclusive IP Zones，不支援 Shared IP Zone。11.4 使用 PF，其餘版本使用 ipfilter。不支援原生 IPSec 與 SecureConnect | `sol5`（i386、sparc） |

## Endpoint VEN

| 作業系統 | 版本 | 安裝包 |
|---|---|---|
| Windows | 11、10（1511 LTSB 至 22H2）、8.1、7 | `win.x86.exe`（32 位元）；`win.exe`（x86_64 與 64 位元 ARM） |
| macOS | 14（Sonoma）、15（Sequoia）、26（Tahoe）、27（GoldenGate） | `mac.universal.pkg` |

- Windows 7 只支援到 TLS 1.1。
- 無線與 VPN 介面的政策強制由 Endpoint VEN 支援。
