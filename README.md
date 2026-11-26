# Home Wi-Fi OpenWrt Mesh (OpenTofu / Terraform)

Declarative Infrastructure as Code and reproducible firmware build pipeline for managing a fleet of OpenWrt Dumb APs (Jio JIDU6411 / AX6000 or any OpenWrt 25.x/26.x device) with Ethernet backhaul, native 802.11r/k/v roaming, `usteer` client steering, hardware offloading, and scheduled status LEDs.

## Features

- **Dumb AP topology:** Bridges all Ethernet ports (`lan1`–`lan4` + `wan`) into `br-lan` and disables `dnsmasq`, `odhcpd`, and `firewall`.
- **Hardware offloading stack (JIDU6411 / IPQ9574 + QCN9074):**
  - `qcom_ppe` L2 hardware switchdev (> 96% wired `wan` to `lan` switching in PPE silicon at < 0.5% CPU).
  - `ath11k` skb-less `page_pool` RX, flat TX/RX tables, REO TCP coalescing, AQL, and fixed QCN9074 TCL hardware TSO (cuts ~925 Mbps Wi-Fi download `sirq` from 38% to 11–13%).
  - See [docs/HARDWARE_OFFLOAD.md](docs/HARDWARE_OFFLOAD.md) for architecture details, local patches (`patches/`), and benchmarks.
- **Native Wi-Fi roaming:** Configures `sae-mixed` (WPA2/WPA3), MFP optional (`ieee80211w=1`), 802.11r Fast Transition, 802.11k RRM, 802.11v BSS Transition, and `usteer` over Ethernet backhaul.
- **Per-AP RF tuning:** Independent 2.4 GHz and 5 GHz channel, width (`HE20`/`HE80`/`HE160`), and TX power per room.
- **LED schedule:** Cron-based night shutoff and daytime status LED without changing the Wi-Fi regulatory country.
- **Live telemetry:** Reads live kernel, radio channels, TX power, and `usteer` peer status into OpenTofu/Terraform outputs.
- **Reproducible CI firmware build:** `.github/workflows/build-jidu6411.yml` builds the complete OpenWrt `6.18` JIDU6411 sysupgrade image with all patches and packages baked in.
- **OSS-safe by default:** All credentials, Wi-Fi passphrases, and private IPs live in `terraform.tfvars` (git-ignored).

## Prerequisites

- [OpenTofu](https://opentofu.org/) (`>= 1.6`) or Terraform (`>= 1.6`)
- `python3` and `ssh`
- OpenWrt APs with `wpad-mesh-mbedtls` (or `wpad-mbedtls`), `usteer`, and SSH key authentication in `/etc/dropbear/authorized_keys`

## Usage

1. Copy the example variables file and edit your private values:
   ```sh
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Initialize providers:
   ```sh
   tofu init
   ```
3. Preview and apply changes:
   ```sh
   tofu plan
   tofu apply
   ```
4. View live fleet status:
   ```sh
   tofu output fleet_live_status
   ```
