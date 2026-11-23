output "fleet_live_status" {
  description = "Live telemetry read from every managed OpenWrt AP."
  value = {
    for name, st in data.external.ap_live_state : name => {
      ip            = var.access_points[name].ip
      reachable     = st.result.reachable
      hostname      = st.result.hostname
      kernel        = st.result.kernel
      wifi_country  = st.result.wifi_country
      radio2g       = st.result.radio2g
      radio5g       = st.result.radio5g
      usteer_peers  = st.result.usteer_peers
      timezone      = st.result.timezone
    }
  }
}
