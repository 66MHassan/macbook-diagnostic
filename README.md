# Mac Hardware Diagnostic

A comprehensive Mac hardware diagnostic and verification script. Run it before buying a used MacBook to detect replaced parts, stolen/locked devices, battery health issues, and more.

## Quick Start

```bash
curl -sL https://raw.githubusercontent.com/majid-rehman/mac-diagnostic/main/mac-diagnostic.sh | bash
```

Or download and run:

```bash
curl -O https://raw.githubusercontent.com/majid-rehman/mac-diagnostic/main/mac-diagnostic.sh
chmod +x mac-diagnostic.sh
./mac-diagnostic.sh
```

## What It Checks

| # | Section | What It Does |
|---|---------|-------------|
| 1 | **System Identity** | Serial number validation, IOKit consistency, UUID cross-check |
| 2 | **Activation Lock / MDM** | MDM enrollment, DEP status, Find My Mac, stolen device indicators |
| 3 | **Usage Timeline** | First boot date, OS reinstall count, user account count |
| 4 | **Battery Authenticity** | Cycle count, capacity, manufacture date, controller chip verification, temperature |
| 5 | **Storage Health** | SMART status, SSD model/serial, wear level (with smartmontools) |
| 6 | **Display** | Screen replacement detection via True Tone/ambient light sensor, ProMotion check |
| 7 | **Camera/Mic/Speakers** | Hardware presence verification |
| 8 | **Keyboard/Trackpad/Touch ID** | Force Touch, Secure Enclave, keyboard backlight detection |
| 9 | **Networking** | WiFi signal strength (RSSI), WiFi 6 support, Bluetooth hardware |
| 10 | **Ports** | USB/Thunderbolt buses, SD card reader, HDMI |
| 11 | **CPU/GPU/Memory** | Core count, thermal throttle history |
| 12 | **Benchmarks** | Single-core & multi-core CPU, sequential disk read/write |
| 13 | **Thermal Stress** | 10-second full-core stress test with throttle detection |
| 14 | **Security** | FileVault, SIP, Gatekeeper, Firewall, Secure Boot |
| 15 | **Serial Consistency** | Cross-references all hardware serials to detect part swaps |
| 16 | **Software** | Third-party LaunchDaemons/Agents, kernel extensions, login items |
| 17 | **Charger** | Genuine Apple verification, wattage check |

## Replaced Part Detection

The script detects hardware replacements through:

- **Battery**: Manufacture date vs system setup date, controller chip (TI bq40z651), cycle count vs age analysis
- **Display**: True Tone calibration data presence, ambient light sensor check
- **Logic Board**: Serial number consistency between IOKit and system_profiler
- **General**: Parts & Service guidance (System Settings > General > About)

## Manual Checks

Some things can't be automated. The script generates a checklist of **29 manual tests** including:

- Dead pixel / burn-in / backlight bleed tests
- Speaker and microphone quality
- Every keyboard key
- Trackpad haptics in all corners
- Touch ID enrollment
- Each port individually
- WiFi/Bluetooth range

## Output

- Color-coded terminal output with PASS/WARN/FAIL
- Clean text report saved to `~/mac-diagnostic-report-YYYYMMDD-HHMMSS.txt`
- Summary with verdict and quick reference card

## Requirements

- macOS (tested on Sequoia 15.x, Apple Silicon)
- No sudo required for core checks
- Optional: `smartmontools` for detailed SSD health (`brew install smartmontools`)

## License

MIT
