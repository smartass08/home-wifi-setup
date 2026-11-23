locals {
  ap_configs = {
    for name, ap in var.access_points : name => {
      hostname        = name
      ip              = ap.ip
      mac             = ap.mac
      gateway         = var.network_gateway
      dns             = var.network_dns
      bridge_ports    = var.bridge_ports
      packet_steering = var.packet_steering ? 1 : 0
      timezone_name   = var.timezone_name
      timezone_posix  = var.timezone_posix
      admin_username  = var.admin_username
      wifi = {
        ssid            = var.wifi.ssid
        country         = var.wifi.country
        encryption      = var.wifi.encryption
        ieee80211w      = var.wifi.ieee80211w
        mobility_domain = var.wifi.mobility_domain
        ft_over_ds      = var.wifi.ft_over_ds
        radio2g_en      = ap.radio2g_en ? 1 : 0
        ch2g            = ap.ch2g
        ht2g            = ap.ht2g
        tx2g            = ap.tx2g
        ch5g            = ap.ch5g
        ht5g            = ap.ht5g
        tx5g            = ap.tx5g
      }
      usteer       = var.usteer
      led_schedule = var.led_schedule
    }
  }
}

# Read live state from every managed AP for drift visibility and outputs
data "external" "ap_live_state" {
  for_each = var.access_points

  program = ["python3", "${path.module}/scripts/read-ap-state.sh"]

  query = {
    ip      = each.value.ip
    user    = var.ssh_user
    keypath = pathexpand(var.ssh_private_key_path)
  }
}

# Declaratively manage each OpenWrt Dumb AP over SSH
resource "terraform_data" "access_point" {
  for_each = local.ap_configs

  input = {
    hostname = each.value.hostname
    ip       = each.value.ip
    mac      = each.value.mac
  }

  triggers_replace = {
    config_json     = jsonencode(each.value)
    wifi_psk_sha256 = sha256(var.wifi.passphrase)
    admin_pw_sha256 = sha256(var.admin_password)
    script_sha256   = filesha256("${path.module}/scripts/apply-ap.sh")
  }

  provisioner "local-exec" {
    interpreter = ["sh", "-c"]
    command     = "${path.module}/scripts/apply-ap.sh"

    environment = {
      AP_CONFIG_JSON = jsonencode(each.value)
      SSH_USER       = var.ssh_user
      SSH_KEY_PATH   = pathexpand(var.ssh_private_key_path)
      WIFI_KEY       = var.wifi.passphrase
      ADMIN_PASSWORD = var.admin_password
    }
  }
}
