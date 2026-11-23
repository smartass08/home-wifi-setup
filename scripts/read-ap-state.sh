#!/usr/bin/env python3
"""Reads live state from an OpenWrt AP over SSH for OpenTofu/Terraform external data source."""
import json
import subprocess
import sys

q = json.load(sys.stdin)
ip = q["ip"]
user = q["user"]
keypath = q["keypath"]

remote_cmd = r"""
h=$(cat /proc/sys/kernel/hostname 2>/dev/null || true)
k=$(uname -r 2>/dev/null || true)
c=$(uci -q get wireless.radio1.country || true)
tz=$(uci -q get system.@system[0].zonename || true)
r2=$(iwinfo phy0-ap0 info 2>/dev/null | awk '/Channel:/{ch=$4; ht=$NF} /Tx-Power:/{tx=$2} END{if(ch) printf "ch %s %s @ %sdBm", ch, ht, tx; else print "disabled"}')
r5=$(iwinfo phy1-ap0 info 2>/dev/null | awk '/Channel:/{ch=$4; ht=$NF} /Tx-Power:/{tx=$2} END{if(ch) printf "ch %s %s @ %sdBm", ch, ht, tx; else print "disabled"}')
peers=$(ubus call usteer remote_hosts 2>/dev/null | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort | tr '\n' ',' | sed 's/,$//' || true)
printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$h" "$k" "$c" "$tz" "$r2" "$r5" "$peers"
"""

res = subprocess.run(
    [
        "ssh",
        "-i", keypath,
        "-o", "IdentitiesOnly=yes",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=8",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        f"{user}@{ip}",
        "sh", "-s",
    ],
    input=remote_cmd,
    text=True,
    capture_output=True,
)

if res.returncode != 0:
    print(json.dumps({
        "reachable": "false",
        "hostname": "",
        "kernel": "",
        "wifi_country": "",
        "timezone": "",
        "radio2g": "",
        "radio5g": "",
        "usteer_peers": "",
    }))
    sys.exit(0)

lines = res.stdout.splitlines() + [""] * 7
print(json.dumps({
    "reachable": "true",
    "hostname": lines[0],
    "kernel": lines[1],
    "wifi_country": lines[2],
    "timezone": lines[3],
    "radio2g": lines[4],
    "radio5g": lines[5],
    "usteer_peers": lines[6],
}))
