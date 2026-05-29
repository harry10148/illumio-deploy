> **適用版本**：Illumio PCE 25.4 / VEN 25.4
> **更新日期**：2026-05-29
> **原始檔**：`tmp/illumio_k8s.txt`

# Illumio Core for Kubernetes 部署

## 1. 目的與適用情境

在 Kubernetes 叢集上使用 Helm 部署 Illumio Core（cVEN + kubelink），涵蓋自簽 CA 匯入至系統與 Kubernetes ConfigMap、Calico `chainInsertMode` 設定、illumio-values.yaml 準備、Helm 安裝與升級，以及離線環境的 Container Image 搬移流程。

## 2. 前置條件

- Kubernetes 叢集已正常運行（含 Calico CNI）
- `kubectl`、`helm`、`podman`（或 docker）已安裝
- PCE 已運行且可從叢集節點連線至 TCP 8443
- 已取得 Illumio Cluster ID、Token、Code
- 自簽 CA 憑證（`root.democa.illumio-demo.com.crt` 或對應檔案）已備妥

## 3. 操作步驟

匯入自簽 CA 至 Kubernetes ConfigMap：

```bash
kubectl -n illumio-system create configmap root-ca-config \
> --from-file=./certs/root.democa.illumio-demo.com.crt
```

設定 Calico chainInsertMode（直接編輯 DaemonSet）：

```bash
kubectl -n kube-system edit ds calico-node
```

在 spec > template > spec > containers 區塊加入：

```
- name: FELIX_CHAININSERTMODE
  value: Append
```

若使用 Calico with Operator，先確認 Operator 存在：

```bash
# 檢查 tigera-operator 的部署
kubectl get deployment -n tigera-operator
# 如果上面沒有，試試 calico-operator
kubectl get deployment -n calico-operator
```

取得並編輯 Installation CR：

```bash
kubectl get installation.operator.tigera.io -o yaml
# 通常只會有一個，名字叫 default.
kubectl edit installation.operator.tigera.io default
```

在 spec 下加入以下區塊：

```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  # ... 其他現有的 spec 配置，比如 cni, calicoNetwork ...
  calicoNetwork:
    node:
      felixConfiguration:
        # 在這裡添加
        chainInsertMode: "Append"

# ... 其他配置 ...
```

準備 `illumio-values.yaml`：

```yaml
pce_url: pce.lab.local:8443
cluster_id: <ILO_CLUSTER_UUID>
cluster_token: <ILO_CLUSTER_TOKEN>
cluster_code: <ILO_CLUSTER_CODE>
containerRuntime: crio
containerManager: kubernetes
extraVolumeMounts:
  - name: root-ca
    mountPath: /etc/pki/tls/ilo_certs/
    readOnly: false
extraVolumes:
  - name: root-ca
    configMap:
        name: root-ca-config
ignore_cert: true
#clusterMode: clas

#pce_url: URL_PORT
#cluster_id: ILO_CLUSTER_UUID
#cluster_token: ILO_CLUSTER_TOKEN
#cluster_code: ILO_CODE
#containerRuntime: RUNTIME # supported values: [containerd (default), docker, crio, k3s_containerd]
#containerManager: MANAGER # supported values: [kubernetes, openshift]
#networkType: flat # CNI type, allowed values are [overlay, flat]
#clusterMode: clas # 
```

Helm 安裝：

```bash
helm install illumio -f illumio-values.yaml oci://quay.io/illumio/illumio --version 5.4.1 --namespace illumio-system --create-namespace
```

Helm 升級：

```bash
helm upgrade illumio oci://quay.io/illumio/illumio  --namespace illumio-system
```

產生 Helm template 進行審查（可選）：

```bash
helm template oci://quay.io/illumio/illumio -f illumio-values.yaml --version 5.4.1 > illumio.yaml
```

離線環境 Container Image 搬移：

```bash
podman pull quay.io/illumio/cven:23.4.5-8-cven2345
podman pull quay.io/illumio/kubelink:5.4.1-4
podman save -o kubelink:5.4.1-4.tar quay.io/illumio/kubelink:5.4.1-4
podman save -o cven_23.4.5-8-cven2345.tar quay.io/illumio/cven:23.4.5-8-cven2345

podman load -i cven_23.4.5-8-cven2345.tar
podman load -i kubelink_5.4.1-4.tar

podman tag quay.io/illumio/kubelink:5.4.1-4 <acr path>/kubelink:5.4.1-4
podman tag quay.io/illumio/cven:23.4.5-8-cven2345 <acr path>/cven:23.4.5-8-cven2345

podman push <acr path>/kubelink:5.2.0-5
podman push <acr path>/cven:23.4.0-8-cven2340
```

## 4. 驗證

```bash
# 確認 illumio-system namespace 下的 Pod 正常運行
kubectl get pods -n illumio-system
```

## 5. 失敗回滾 / 救援

- — 無 —

若 Helm 安裝失敗，確認 `illumio-values.yaml` 中的 `cluster_id`、`cluster_token`、`cluster_code` 正確，且 PCE 可連通。

## 6. 原廠文件參照

- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Kubernetes and Openshift > Deployment with Helm Chart (Kubernetes 3.0.0 and Later) — Helm chart 從 oci://quay.io/illumio/illumio 部署，含 cVEN + Kubelink
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Helm Chart Parameters — pce_url、cluster_id、cluster_token、cluster_code、containerRuntime（containerd/crio/k3s_containerd）、extraVolumes/extraVolumeMounts
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Configure Calico in Append Mode — DaemonSet 編輯加入 FELIX_CHAININSERTMODE: Append，以及 Operator 方式（tigera-operator Installation CR）
- [NotebookLM] Install, Configure, and Upgrade Guide 25.4 §Implement Kubelink with a Private PKI — ignore_cert: true 適用於自簽憑證，extraVolumes 掛載 ConfigMap CA

## 7. 與原廠差異（若有）

- **Helm values 參數**：SOP 的 illumio-values.yaml（pce_url、cluster_id、cluster_token、cluster_code、containerRuntime: crio、extraVolumes、ignore_cert）與原廠（Install_Upgrade §Helm Chart Parameters）完全對應。
- **Calico Operator 方式**：SOP 提供 tigera-operator Installation CR 的 chainInsertMode 設定，原廠未明確記錄此進階用法，SOP 補強合理。
- **離線 Image 搬移**：podman save/load/tag/push 流程原廠未記錄（屬環境適配），SOP 補強合理。
