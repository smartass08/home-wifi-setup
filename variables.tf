variable "ssh_user" {
  description = "SSH user used by OpenTofu/Terraform to manage OpenWrt APs."
  type        = string
  default     = "root"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key authorized on the OpenWrt APs."
  type        = string
}

variable "admin_username" {
  description = "Additional admin username for SSH and LuCI (besides root)."
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Password for root and admin_username on all APs."
  type        = string
  sensitive   = true
}

variable "timezone_name" {
  description = "IANA timezone name for system clock (does not affect Wi-Fi country)."
  type        = string
  default     = "UTC"
}

variable "timezone_posix" {
  description = "POSIX timezone string matching timezone_name (for example, IST-5:30)."
  type        = string
  default     = "GMT0"
}

variable "network_gateway" {
  description = "Upstream router/gateway IP for Dumb AP management traffic."
  type        = string
}

variable "network_dns" {
  description = "DNS server IP for Dumb AP management traffic."
  type        = string
}

variable "bridge_ports" {
  description = "Ethernet ports bridged into br-lan on each Dumb AP."
  type        = list(string)
  default     = ["lan1", "lan2", "lan3", "lan4", "wan"]
}

variable "packet_steering" {
  description = "Enable OpenWrt multi-core packet steering."
  type        = bool
  default     = true
}

variable "wifi" {
  description = "Shared Wi-Fi SSID, security, country, and 802.11r/k/v roaming settings."
  type = object({
    ssid            = string
    passphrase      = string
    country         = string
    encryption      = string
    ieee80211w      = number
    mobility_domain = string
    ft_over_ds      = number
  })
  sensitive = true
}

variable "usteer" {
  description = "Shared usteer client roaming and band-steering thresholds."
  type = object({
    roam_scan_snr           = number
    roam_trigger_snr        = number
    signal_diff_threshold   = number
    band_steering_interval  = number
    band_steering_min_snr   = number
  })
  default = {
    roam_scan_snr          = -65
    roam_trigger_snr       = -72
    signal_diff_threshold  = 10
    band_steering_interval = 30000
    band_steering_min_snr  = -60
  }
}

variable "led_schedule" {
  description = "Cron schedule for turning status LEDs off at night and on during the day."
  type = object({
    enabled  = bool
    off_hour = number
    on_hour  = number
    day_led  = string
  })
  default = {
    enabled  = true
    off_hour = 21
    on_hour  = 11
    day_led  = "green:status"
  }
}

variable "access_points" {
  description = "Map of OpenWrt Dumb APs managed in this mesh fleet."
  type = map(object({
    ip         = string
    mac        = string
    radio2g_en = bool
    ch2g       = number
    ht2g       = string
    tx2g       = number
    ch5g       = number
    ht5g       = string
    tx5g       = number
  }))
}
