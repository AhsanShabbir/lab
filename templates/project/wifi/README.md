# WiFi lab — __TARGET__

**Authorized use only.** Only attack networks you own. Add your lab SSID or BSSID to `config/wifi-allowlist.txt` before capture/crack.

## Quick start

```bash
# From lab root
./setup-wifi-tools.sh
./wifi --scan
```

## Manual capture (Mac v1)

Built-in Mac WiFi cannot run Linux monitor-mode tools. Use Apple’s sniffer:

1. **Option-click** the Wi-Fi menu → **Open Wireless Diagnostics**
2. **Window → Sniffer** (or **Perform Wi-Fi Sniff**)
3. Set **channel** and **width** to match your **lab AP**
4. Start sniff, reproduce association to the lab AP (connect a test device), stop and save `.pcapng`
5. Copy the file to:

   `projects/__TARGET__/wifi/capture/inbox/`

6. Convert and crack:

   ```bash
   ./wifi --target 1 --only capture
   ./wifi --target 1 --crack
   ```

## Outputs

| Path | Description |
|------|-------------|
| `scan/networks.txt` | Numbered AP list |
| `scan/networks.json` | Scan JSON |
| `crack/handshake.22000` | Hashcat input |
| `crack/result.txt` | Crack status |
| `run.log` | Pipeline log |

## Wordlist

Default: `wordlists/wifi-common.txt`. Override in `config/wifi.defaults`.

## Phase 2 (Linux VM)

When you have a USB adapter + Kali VM, set `WIFI_HOST` in `config/wifi.defaults` for automated remote capture (not yet wired in v1).
