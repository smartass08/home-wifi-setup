# Hardware offloading on Jio JIDU6411 (IPQ9574 + QCN9074)

This document explains the open-source hardware offloading stack built for OpenWrt `6.18.x` on the Jio JIDU6411 (`IPQ9554`/`IPQ9574` SoC + internal 2.4 GHz `ath11k_ahb` + PCIe 5 GHz `QCN9074` `ath11k_pci`) in Ethernet-backhaul Dumb AP mode.

## Silicon boundaries

The JIDU6411 pairs a Wi-Fi 7 generation SoC (`IPQ9574`) with Wi-Fi 6 Lithium generation radios (`QCN9074` and the internal `IPQ9574` 2.4 GHz radio).

- **Wired-to-wired (`wan` to `lan1`–`lan4`):** The `IPQ9574` Packet Processing Engine (`qcom_ppe` / APPE) switches Ethernet frames in silicon with near-zero CPU use once L2 switchdev is enabled.
- **Wired-to-Wi-Fi (`wan` to `phy0-ap0` / `phy1-ap0`):** Neither `QCN9074` nor the internal `IPQ9574` 2.4 GHz radio has PPE Direct Switch (`ppe_ds`) hardware rings (`REO2PPE`, `PPE2TCL`, `WBM_PPE_RELEASE` are absent in Lithium silicon).
  Every Wi-Fi packet crosses the ARM CPU once between EDMA and `ath11k`.
- **What `QCN9074` and `IPQ9574` radios do offload in hardware:**
  - AES-CCMP WPA2/WPA3 encryption (`crypto_mode=0`).
  - 802.3 Ethernet to 802.11 frame encapsulation and decapsulation (`frame_mode=2`).
  - Hardware Toeplitz 5-tuple RX hashing (`skb_set_hash`).
  - TCL hardware TCP Segmentation Offload (TSO) and scatter-gather (`HAL_TX_MSDU_EXTENSION`).

## Stack components

### Phase 1: `qcom_ppe` L2 hardware switchdev

Enables the IPQ9574 PPE switch core for `br-lan` while keeping the Linux bridge as the source of truth for roaming and multicast.

- Upstream L2 patches from `VIKINGYFY/immortalwrt` (`0500-02` through `0505-02`, `0620`, `0690`), omitting the buggy TX flood bitmap patch (`0505-04`) and all L3/NAT virtual-port code.
- Local patch `patches/qualcommbe/0693-net-ppe-preserve-mac-tx-across-bridge-detach.patch`:
  - Preserves `PPE_PORT_BRIDGE_TXMAC_EN` across bridge detach (uses STP disabled state during teardown so EDMA-directed TX keeps working).
  - Casts `const struct net_device *` in `ppe_bridge_foreign_dev_check()` for Linux `6.18.64` `-Werror=discarded-qualifiers`.
- Roaming safety: Wi-Fi client MACs are shadowed to CPU port `0`, and station moves on wired ports trap to CPU port `0` so 802.11r/k/v handoffs update FDB entries without blackholes.

### Phase 2 and 3a: `ath11k` zero-copy, REO coalescing, and AQL

Applies the `openwrt/openwrt#26075` datapath stack (`ath11k` `970`–`9928` excluding `qualcommax`-only `9926`, plus `mac80211` `subsys` `514`–`522`):

- Per-radio skb-less `page_pool` RX refill and flat TX/RX buffer tables replacing per-packet IDR lookups.
- In-driver REO TCP segment coalescing (`9921`), REO descriptor prefetching (`9917`), batched cached-ring DMA invalidation (`9916`), and partial RX DMA sync (`9920`).
- TX flow control, Airtime Queue Limits (`aql_enable=1`, `5000`/`12000` µs), and bidirectional airtime fairness (`#25981`).
- Native kernel multi-core IRQ spreading for EDMA RX (`#26741`), EDMA TX completion wake fix (`#26461`), and QCN9074 PCIe MSI DP rings (`#26253`).

### Phase 3b: QCN9074 and IPQ9574 TCL hardware TSO fix

Local patch `patches/ath11k/9930-wifi-ath11k-enable-tcl-tso-on-ipq9574-and-qcn9074.patch`:

1. Enables `.tx_tso = true` for `ATH11K_HW_QCN9074_HW10` and `ATH11K_HW_IPQ9574` in `drivers/net/wireless/ath/ath11k/core.c`.
2. Fixes a bridged-GRO checksum bug in `drivers/net/wireless/ath/ath11k/dp_tx.c`:
   - `qcom_ppe` EDMA marks verified RX packets as `CHECKSUM_UNNECESSARY` rather than `CHECKSUM_PARTIAL`.
   - When GRO coalesces those bridged packets into a 64 KB GSO batch, `if (skb->ip_summed == CHECKSUM_PARTIAL)` evaluated to `false` and left TCL IP/TCP checksum offload disabled.
   - Changing the condition to `if (tso || skb->ip_summed == CHECKSUM_PARTIAL)` ensures TCL hardware recomputes IPv4 and TCP checksums for every segmented frame.

## Measured benchmarks (JIDU6411, 1.10 GHz)

| Metric | Baseline `6.18.64` | Full offload (`Phase 1 + 2 + 3b`) |
| :--- | :---: | :---: |
| Pure-LAN Wi-Fi download (`iperf3 -P 4 -R`, 160 MHz) | ~866 Mbps | **916–925 Mbps** |
| CPU `sirq` under ~925 Mbps Wi-Fi download | 38% `sirq` (61% idle) | **11–13% `sirq` (85–87% idle)** |
| Pure-LAN Wi-Fi upload (`iperf3 -P 4`, 160 MHz) | ~940 Mbps | **936 Mbps** (0 retransmits, 13–16% `sirq`) |
| Loaded LAN ping during 936 Mbps Wi-Fi download | — | **6.01 ms avg** (8.68 ms max, 0% loss) |
| Wired `wan` to `lan` switching (`qcom_ppe` L2) | 6–8% `sirq` | **< 0.5% `sirq`** (> 96% switched in PPE silicon) |
| Available RAM (512 MB unit) | ~113 MB | **153–182 MB** |

## Verification commands

Run these commands on an AP after flashing:

```sh
# 1. Confirm QCN9074 TCL hardware TSO and scatter-gather are active
ethtool -k phy1-ap0 | grep -E "scatter-gather|tcp-segmentation"

# 2. Confirm qcom_ppe L2 switchdev is active and wired frames bypass CPU port 0
cat /sys/class/net/wan/phys_switch_id
cat /sys/kernel/debug/ppe/l2_forward
cat /sys/kernel/debug/ppe/port_rx
cat /sys/kernel/debug/ppe/port_tx

# 3. Confirm AQL and airtime fairness are active
cat /sys/kernel/debug/ieee80211/phy1/aql_enable
cat /sys/kernel/debug/ieee80211/phy1/airtime_flags
```
