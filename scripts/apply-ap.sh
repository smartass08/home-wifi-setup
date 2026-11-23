#!/bin/sh
# Idempotently applies desired OpenWrt Dumb AP + Wi-Fi mesh + usteer + LED schedule over SSH.
set -e

eval "$(python3 -c '
import json, os, shlex
cfg = json.loads(os.environ["AP_CONFIG_JSON"])
w = cfg["wifi"]
u = cfg["usteer"]
led = cfg["led_schedule"]
vals = {
    "AP_HOST": cfg["hostname"],
    "AP_IP": cfg["ip"],
    "GATEWAY": cfg["gateway"],
    "DNS": cfg["dns"],
    "PORTS": " ".join(cfg["bridge_ports"]),
    "PKT_STEER": str(cfg["packet_steering"]),
    "TZ_NAME": cfg["timezone_name"],
    "TZ_POSIX": cfg["timezone_posix"],
    "ADMIN_USER": cfg["admin_username"],
    "SSID": w["ssid"],
    "COUNTRY": w["country"],
    "ENCRYPTION": w["encryption"],
    "IEEE80211W": str(w["ieee80211w"]),
    "MOBILITY_DOMAIN": w["mobility_domain"],
    "FT_OVER_DS": str(w["ft_over_ds"]),
    "R2_EN": str(w["radio2g_en"]),
    "CH2G": str(w["ch2g"]),
    "HT2G": w["ht2g"],
    "TX2G": str(w["tx2g"]),
    "CH5G": str(w["ch5g"]),
    "HT5G": w["ht5g"],
    "TX5G": str(w["tx5g"]),
    "ROAM_SCAN": str(u["roam_scan_snr"]),
    "ROAM_TRIG": str(u["roam_trigger_snr"]),
    "SIG_DIFF": str(u["signal_diff_threshold"]),
    "BS_INT": str(u["band_steering_interval"]),
    "BS_SNR": str(u["band_steering_min_snr"]),
    "LED_EN": "1" if led["enabled"] else "0",
    "LED_OFF_HR": str(led["off_hour"]),
    "LED_ON_HR": str(led["on_hour"]),
    "LED_DAY": led["day_led"],
}
for k, v in vals.items():
    print(f"{k}={shlex.quote(v)}")
')"

SSH_OPTS="-i ${SSH_KEY_PATH} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
NOW_UTC=$(date -u +"%Y-%m-%d %H:%M:%S")

echo "[*] Applying declarative config to ${AP_HOST} (${AP_IP})..."

ssh $SSH_OPTS "${SSH_USER}@${AP_IP}" sh -s <<REMOTE
set -e

# 1. System hostname & timezone
uci set system.@system[0].hostname='${AP_HOST}'
uci set system.@system[0].zonename='${TZ_NAME}'
uci set system.@system[0].timezone='${TZ_POSIX}'

# Ensure all status LEDs default off at boot
for led in blue:status green:status red:status; do
  sec="led_\$(echo "\$led" | tr ':' '_')"
  uci set "system.\${sec}=led"
  uci set "system.\${sec}.name=\${led}"
  uci set "system.\${sec}.sysfs=\${led}"
  uci set "system.\${sec}.trigger=none"
  uci set "system.\${sec}.default=0"
done

SYS_CHANGED=\$(uci changes system)
if [ -n "\$SYS_CHANGED" ]; then
  uci commit system
  /etc/init.d/system reload
  /etc/init.d/led restart 2>/dev/null || true
fi

# 2. Dumb AP network settings
uci -q delete network.wan || true
uci -q delete network.wan6 || true
uci -q delete network.@device[0].ports || true
for p in ${PORTS}; do
  uci add_list network.@device[0].ports="\$p"
done
uci -q delete network.lan.ipaddr || true
uci add_list network.lan.ipaddr='${AP_IP}/24'
uci set network.lan.gateway='${GATEWAY}'
uci -q delete network.lan.dns || true
uci add_list network.lan.dns='${DNS}'
uci set network.globals.packet_steering='${PKT_STEER}'

NET_CHANGED=\$(uci changes network)
if [ -n "\$NET_CHANGED" ]; then
  uci commit network
  /etc/init.d/network reload
fi

# 3. Disable DHCP / DNS / RA / Firewall
uci set dhcp.lan.ignore='1'
if [ -n "\$(uci changes dhcp)" ]; then
  uci commit dhcp
fi
for svc in dnsmasq odhcpd firewall; do
  if [ -x "/etc/init.d/\$svc" ]; then
    "/etc/init.d/\$svc" disable 2>/dev/null || true
    "/etc/init.d/\$svc" stop 2>/dev/null || true
  fi
done

# 4. Wi-Fi radios & 802.11r/k/v
uci set wireless.radio0.country='${COUNTRY}'
uci set wireless.radio0.channel='${CH2G}'
uci set wireless.radio0.htmode='${HT2G}'
uci set wireless.radio0.txpower='${TX2G}'
if [ '${R2_EN}' = '1' ]; then
  uci set wireless.radio0.disabled='0'
  uci set wireless.default_radio0.disabled='0'
else
  uci set wireless.radio0.disabled='1'
  uci set wireless.default_radio0.disabled='1'
fi

uci set wireless.radio1.country='${COUNTRY}'
uci set wireless.radio1.channel='${CH5G}'
uci set wireless.radio1.htmode='${HT5G}'
uci set wireless.radio1.txpower='${TX5G}'
uci set wireless.radio1.disabled='0'
uci set wireless.default_radio1.disabled='0'

for iface in default_radio0 default_radio1; do
  uci set wireless.\${iface}.network='lan'
  uci set wireless.\${iface}.mode='ap'
  uci set wireless.\${iface}.ssid='${SSID}'
  uci set wireless.\${iface}.encryption='${ENCRYPTION}'
  uci set wireless.\${iface}.key='${WIFI_KEY}'
  uci set wireless.\${iface}.ieee80211w='${IEEE80211W}'
  uci set wireless.\${iface}.ieee80211r='1'
  uci set wireless.\${iface}.mobility_domain='${MOBILITY_DOMAIN}'
  uci set wireless.\${iface}.ft_over_ds='${FT_OVER_DS}'
  uci set wireless.\${iface}.ft_psk_generate_local='1'
  uci set wireless.\${iface}.ieee80211k='1'
  uci set wireless.\${iface}.rrm_neighbor_report='1'
  uci set wireless.\${iface}.rrm_beacon_report='1'
  uci set wireless.\${iface}.ieee80211v='1'
  uci set wireless.\${iface}.bss_transition='1'
  uci set wireless.\${iface}.wnm_sleep_mode='1'
  uci set wireless.\${iface}.time_advertisement='2'
done

WIFI_CHANGED=\$(uci changes wireless)
if [ -n "\$WIFI_CHANGED" ]; then
  uci commit wireless
  (sleep 1; wifi reload) >/dev/null 2>&1 &
fi

# 5. usteer mesh steering
uci set usteer.@usteer[0].network='lan'
uci set usteer.@usteer[0].local_mode='0'
uci -q delete usteer.@usteer[0].ssid_list || true
uci add_list usteer.@usteer[0].ssid_list='${SSID}'
uci set usteer.@usteer[0].roam_scan_snr='${ROAM_SCAN}'
uci set usteer.@usteer[0].roam_trigger_snr='${ROAM_TRIG}'
uci set usteer.@usteer[0].signal_diff_threshold='${SIG_DIFF}'
uci set usteer.@usteer[0].band_steering_interval='${BS_INT}'
uci set usteer.@usteer[0].band_steering_min_snr='${BS_SNR}'

USTEER_CHANGED=\$(uci changes usteer)
if [ -n "\$USTEER_CHANGED" ]; then
  uci commit usteer
  /etc/init.d/usteer enable
  /etc/init.d/usteer restart
fi

# 6. Admin user in rpcd + cron LED schedule
if [ -n '${ADMIN_USER}' ] && [ '${ADMIN_USER}' != 'root' ]; then
  grep -q "^${ADMIN_USER}:" /etc/passwd || echo "${ADMIN_USER}:x:0:0:${ADMIN_USER}:/root:/bin/ash" >> /etc/passwd
  grep -q "^${ADMIN_USER}:" /etc/shadow || echo "${ADMIN_USER}:*:0:0:99999:7:::" >> /etc/shadow
  if ! grep -q "option username '${ADMIN_USER}'" /etc/config/rpcd; then
    s=\$(uci add rpcd login)
    uci set rpcd.\$s.username='${ADMIN_USER}'
    uci set rpcd.\$s.password='\$p\$${ADMIN_USER}'
    uci add_list rpcd.\$s.read='*'
    uci add_list rpcd.\$s.write='*'
    uci commit rpcd
    /etc/init.d/rpcd restart
  fi
fi

date -u -s '${NOW_UTC}' >/dev/null 2>&1 || true

if [ '${LED_EN}' = '1' ]; then
  mkdir -p /etc/crontabs
  touch /etc/crontabs/root
  sed -i '/\/sys\/class\/leds\//d' /etc/crontabs/root
  echo "0 ${LED_OFF_HR} * * * for l in /sys/class/leds/*/brightness; do echo 0 > \\\$l; done" >> /etc/crontabs/root
  echo "0 ${LED_ON_HR} * * * cat /sys/class/leds/${LED_DAY}/max_brightness > /sys/class/leds/${LED_DAY}/brightness" >> /etc/crontabs/root
  /etc/init.d/cron enable
  /etc/init.d/cron restart
fi

sync
echo "[+] ${AP_HOST} (${AP_IP}) converged."
REMOTE
