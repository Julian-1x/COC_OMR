# Public internet access (no DuckDNS)

Production hostname: **phinma-coc-omr.omr**

## Campus (works today)

- PC: hosts file → `http://phinma-coc-omr.omr/login`
- Phones on same Wi-Fi: `http://192.168.254.101/login` (or school DNS below)

## Phones + web on school Wi-Fi (recommended)

School IT adds **one DNS A record**:

```
phinma-coc-omr.omr  →  192.168.254.101
```

Then teachers use the **same URL** on PC and phone:

**http://phinma-coc-omr.omr/login**

## Access from anywhere (LTE, home Wi-Fi)

1. Router **port forward** TCP 80 (and 443 for HTTPS later) → `192.168.254.101`
2. School IT publishes **phinma-coc-omr.omr** (or a real domain like `omr.phinma.edu.ph`) to your **public IP**
3. Add HTTPS with win-acme or school certificate

Without public DNS, the internet cannot resolve `.omr` names — that is normal.

## Windows firewall (Admin, once)

```powershell
New-NetFirewallRule -DisplayName "COC OMR HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
```
