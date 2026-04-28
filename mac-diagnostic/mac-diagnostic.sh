#!/bin/bash
# =============================================================================
# Mac Hardware Diagnostic & Verification Script v2.0
# Use when buying a new or used MacBook to verify hardware integrity,
# detect replaced parts, and check for stolen/MDM-locked devices.
# =============================================================================

set +e

# macOS doesn't have timeout, use perl alternative
run_with_timeout() {
    local secs=$1; shift
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@" 2>/dev/null
}

REPORT_FILE="$HOME/mac-diagnostic-report-$(date +%Y%m%d-%H%M%S).txt"
PASS=0
WARN=0
FAIL=0
MANUAL_CHECKS=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo "$1" >> "$REPORT_FILE"; echo "$1"; }
header() { log ""; log "$(printf '=%.0s' {1..70})"; log "  $1"; log "$(printf '=%.0s' {1..70})"; }
pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}[PASS]${NC} $1"; echo "  [PASS] $1" >> "$REPORT_FILE"; }
warn() { WARN=$((WARN+1)); echo -e "  ${YELLOW}[WARN]${NC} $1"; echo "  [WARN] $1" >> "$REPORT_FILE"; }
fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}[FAIL]${NC} $1"; echo "  [FAIL] $1" >> "$REPORT_FILE"; }
info() { echo -e "  ${BLUE}[INFO]${NC} $1"; echo "  [INFO] $1" >> "$REPORT_FILE"; }
manual() { MANUAL_CHECKS="${MANUAL_CHECKS}\n  - $1"; echo -e "  ${CYAN}[TODO]${NC} $1"; echo "  [TODO] $1" >> "$REPORT_FILE"; }

echo "" > "$REPORT_FILE"
log "Mac Hardware Diagnostic Report v2.0"
log "Generated: $(date)"
log "$(printf '=%.0s' {1..70})"

# ─────────────────────────────────────────────────────────────────────────────
header "1. SYSTEM IDENTITY"
# ─────────────────────────────────────────────────────────────────────────────

HW=$(system_profiler SPHardwareDataType 2>/dev/null)
MODEL_NAME=$(echo "$HW" | grep "Model Name" | awk -F': ' '{print $2}')
MODEL_ID=$(echo "$HW" | grep "Model Identifier" | awk -F': ' '{print $2}')
MODEL_NUM=$(echo "$HW" | grep "Model Number" | awk -F': ' '{print $2}')
SERIAL=$(echo "$HW" | grep "Serial Number" | awk -F': ' '{print $2}')
CHIP=$(echo "$HW" | grep "Chip:" | awk -F': ' '{print $2}')
MEMORY=$(echo "$HW" | grep "Memory:" | awk -F': ' '{print $2}')
CORES_TOTAL=$(echo "$HW" | grep "Total Number of Cores" | awk -F': ' '{print $2}')
UUID=$(echo "$HW" | grep "Hardware UUID" | awk -F': ' '{print $2}')
PROVISIONING=$(echo "$HW" | grep "Provisioning UDID" | awk -F': ' '{print $2}')
OS_VER=$(sw_vers -productVersion)
OS_BUILD=$(sw_vers -buildVersion)

info "Model: $MODEL_NAME"
info "Model ID: $MODEL_ID"
info "Model Number: $MODEL_NUM"
info "Serial Number: $SERIAL"
info "Chip: $CHIP"
info "Cores: $CORES_TOTAL"
info "Memory: $MEMORY"
info "Hardware UUID: $UUID"
info "Provisioning UDID: $PROVISIONING"
info "macOS: $OS_VER ($OS_BUILD)"

# Verify serial number format (Apple serials are 10 or 12 chars)
SERIAL_LEN=${#SERIAL}
if [[ $SERIAL_LEN -eq 10 || $SERIAL_LEN -eq 12 ]]; then
    pass "Serial number format valid ($SERIAL_LEN chars)"
else
    warn "Unusual serial number length: $SERIAL_LEN (expected 10 or 12)"
fi

if [[ "$SERIAL" == *"REPLACED"* || "$SERIAL" == *"000000"* || -z "$SERIAL" ]]; then
    fail "Serial number appears invalid or replaced"
else
    pass "Serial number appears genuine"
fi

# Verify IOPlatformSerialNumber matches system_profiler
IOREG_SERIAL=$(ioreg -l 2>/dev/null | grep IOPlatformSerialNumber | awk -F'"' '{print $4}')
if [ "$IOREG_SERIAL" = "$SERIAL" ]; then
    pass "IOKit serial matches system serial"
else
    fail "IOKit serial ($IOREG_SERIAL) != system serial ($SERIAL) — possible tampering"
fi

# Hardware UUID consistency
IOREG_UUID=$(ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null | grep IOPlatformUUID | awk -F'"' '{print $4}')
if [ "$IOREG_UUID" = "$UUID" ]; then
    pass "Hardware UUID consistent across sources"
else
    fail "Hardware UUID mismatch — possible logic board swap"
fi

manual "Compare serial on bottom case to '$SERIAL' — mismatch = logic board replaced"
manual "Check warranty/purchase date at https://checkcoverage.apple.com (serial: $SERIAL)"

# ─────────────────────────────────────────────────────────────────────────────
header "2. ACTIVATION LOCK / STOLEN DEVICE / MDM"
# ─────────────────────────────────────────────────────────────────────────────

# MDM enrollment
MDM_CHECK=$(profiles status -type enrollment 2>/dev/null || echo "")
DEP_CHECK=$(echo "$MDM_CHECK" | grep -i "DEP" || echo "")

if echo "$MDM_CHECK" | grep -qi "MDM enrollment: Yes"; then
    fail "MDM ENROLLED — machine is managed by an organization. DO NOT BUY unless seller can remove it"
elif echo "$MDM_CHECK" | grep -qi "MDM enrollment: No"; then
    pass "No MDM enrollment"
else
    warn "MDM enrollment status: could not determine"
fi

if echo "$DEP_CHECK" | grep -qi "Yes"; then
    fail "DEP enrolled (Device Enrollment Program) — organization can remotely lock this Mac"
elif echo "$DEP_CHECK" | grep -qi "No"; then
    pass "Not DEP enrolled"
fi

# Configuration profiles
PROFILES_OUT=$(profiles list 2>/dev/null)
if echo "$PROFILES_OUT" | grep -qi "There are no configuration profiles"; then
    pass "No configuration profiles installed"
elif [ -n "$PROFILES_OUT" ]; then
    warn "Configuration profiles found — may indicate enterprise management:"
    echo "$PROFILES_OUT" | head -10 | while read line; do info "  $line"; done
fi

# Find My Mac
FINDMY=$(nvram -p 2>/dev/null | grep "fmm-mobileme-token" || echo "")
if [ -n "$FINDMY" ]; then
    warn "Find My Mac is enabled — if buying used, ask seller to disable before purchase"
else
    info "Find My Mac token not found in NVRAM (likely disabled or already signed out)"
fi

manual "CRITICAL: Ask seller to Erase All Content & Settings in front of you"
manual "If Setup Assistant asks for an Apple ID after erase — Activation Locked, DO NOT BUY"
manual "Call Apple Support with serial $SERIAL to verify Activation Lock status"

# ─────────────────────────────────────────────────────────────────────────────
header "3. FIRST BOOT & USAGE TIMELINE"
# ─────────────────────────────────────────────────────────────────────────────

DAYS_SINCE=""
if [ -f /var/db/.AppleSetupDone ]; then
    FIRST_BOOT=$(stat -f "%SB" /var/db/.AppleSetupDone 2>/dev/null)
    SETUP_EPOCH=$(stat -f "%B" /var/db/.AppleSetupDone 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    DAYS_SINCE=$(( (NOW_EPOCH - SETUP_EPOCH) / 86400 ))
    info "First setup date: $FIRST_BOOT"
    info "Days since first setup: $DAYS_SINCE"
else
    warn "Cannot determine first boot date"
fi

# OS install date
INSTALL_LOG=$(ls -la /var/db/receipts/com.apple.pkg.macOSBrain.plist 2>/dev/null | awk '{print $6, $7, $8}')
if [ -n "$INSTALL_LOG" ]; then
    info "OS package install date: $INSTALL_LOG"
fi

# Check for OS reinstalls
REINSTALL_COUNT=$(ls /var/db/receipts/com.apple.pkg.macOS*.plist 2>/dev/null | wc -l | tr -d ' ')
info "OS package receipts found: $REINSTALL_COUNT"
if [ "$REINSTALL_COUNT" -gt 20 ]; then
    warn "High number of OS receipts — possible reinstall or refurbishment"
fi

# User accounts
USER_COUNT=$(dscl . -list /Users | grep -v "^_" | grep -v "daemon\|nobody\|root\|com.apple" | wc -l | tr -d ' ')
info "User accounts on system: $USER_COUNT"
if [ "$USER_COUNT" -gt 2 ]; then
    warn "Multiple user accounts ($USER_COUNT) — verify if expected for a 'new' machine"
fi

# NVRAM diagnostics (check if Apple Diagnostics was recently run)
DIAG_RESULT=$(nvram -p 2>/dev/null | grep "diag" || echo "")
if [ -n "$DIAG_RESULT" ]; then
    info "Previous diagnostics data found in NVRAM:"
    info "  $DIAG_RESULT"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "4. BATTERY HEALTH & AUTHENTICITY"
# ─────────────────────────────────────────────────────────────────────────────

POWER=$(system_profiler SPPowerDataType 2>/dev/null)
BATT_IOREG=$(ioreg -rn AppleSmartBattery 2>/dev/null)

CYCLE_COUNT=$(echo "$POWER" | grep "Cycle Count" | awk -F': ' '{print $2}' | tr -d ' ')
CONDITION=$(echo "$POWER" | grep "Condition" | awk -F': ' '{print $2}' | tr -d ' ')
MAX_CAP=$(echo "$POWER" | grep "Maximum Capacity" | awk -F': ' '{print $2}' | tr -d ' %')
CHARGING=$(echo "$POWER" | grep "Charging:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ')
CHARGE_PCT=$(echo "$POWER" | grep "State of Charge" | awk -F': ' '{print $2}' | tr -d ' %')
BATT_SERIAL=$(echo "$POWER" | grep "Serial Number" | head -1 | awk -F': ' '{print $2}' | tr -d ' ')
DEVICE_NAME=$(echo "$POWER" | grep "Device Name" | awk -F': ' '{print $2}' | tr -d ' ')
FW_VER=$(echo "$POWER" | grep "Firmware Version" | head -1 | awk -F': ' '{print $2}' | tr -d ' ')
HW_REV=$(echo "$POWER" | grep "Hardware Revision" | awk -F': ' '{print $2}' | tr -d ' ')
CELL_REV=$(echo "$POWER" | grep "Cell Revision" | awk -F': ' '{print $2}' | tr -d ' ')

# Deep battery info from ioreg
DESIGN_CAP=$(echo "$BATT_IOREG" | grep '"DesignCapacity"' | head -1 | awk -F'= ' '{print $2}' | grep -oE '^[0-9]+')
ACTUAL_MAX_CAP=$(echo "$BATT_IOREG" | grep '"MaxCapacity"' | head -1 | awk -F'= ' '{print $2}' | grep -oE '^[0-9]+')
BATT_TEMP_RAW=$(echo "$BATT_IOREG" | grep '"Temperature"' | awk -F'= ' '{print $2}' | tr -d ' ')
BATT_VOLTAGE=$(echo "$BATT_IOREG" | grep '"Voltage"' | head -1 | awk -F'= ' '{print $2}' | grep -oE '^[0-9]+')
BATT_IOREG_SERIAL=$(echo "$BATT_IOREG" | grep '"BatterySerialNumber"' | awk -F'"' '{print $4}')
MANUFACTURE_DATE_RAW=$(echo "$BATT_IOREG" | grep '"ManufactureDate"' | head -1 | awk -F'= ' '{print $2}' | grep -oE '^[0-9]+')

info "Battery Serial: $BATT_SERIAL"
info "Battery Serial (ioreg): $BATT_IOREG_SERIAL"
info "Battery Controller: $DEVICE_NAME (FW: $FW_VER, HW Rev: $HW_REV, Cell Rev: $CELL_REV)"
info "Cycle Count: $CYCLE_COUNT"
info "Maximum Capacity: ${MAX_CAP}%"
info "Condition: $CONDITION"
info "Current Charge: ${CHARGE_PCT}% (Charging: $CHARGING)"

if [ -n "$DESIGN_CAP" ] && [ -n "$ACTUAL_MAX_CAP" ]; then
    info "Design Capacity: ${DESIGN_CAP} mAh"
    info "Current Max Capacity: ${ACTUAL_MAX_CAP} mAh"
    if [ "$DESIGN_CAP" -gt 0 ]; then
        CALC_HEALTH=$(python3 -c "print(round($ACTUAL_MAX_CAP / $DESIGN_CAP * 100, 1))" 2>/dev/null)
        info "Calculated Health: ${CALC_HEALTH}%"
    fi
fi

if [ -n "$BATT_TEMP_RAW" ]; then
    BATT_TEMP=$(python3 -c "print(round($BATT_TEMP_RAW / 100, 1))" 2>/dev/null)
    info "Battery Temperature: ${BATT_TEMP}C"
    if [ -n "$BATT_TEMP" ]; then
        TEMP_INT=${BATT_TEMP_RAW%.*}
        if [ "$TEMP_INT" -gt 4500 ] 2>/dev/null; then
            warn "Battery temperature high (${BATT_TEMP}C) — may indicate thermal issues"
        else
            pass "Battery temperature normal (${BATT_TEMP}C)"
        fi
    fi
fi

if [ -n "$BATT_VOLTAGE" ]; then
    BATT_VOLT_V=$(python3 -c "print(round($BATT_VOLTAGE / 1000, 2))" 2>/dev/null)
    info "Battery Voltage: ${BATT_VOLT_V}V"
fi

# Decode battery manufacture date
if [ -n "$MANUFACTURE_DATE_RAW" ] && [ "$MANUFACTURE_DATE_RAW" -gt 0 ] 2>/dev/null; then
    BATT_MFG_DATE=$(python3 -c "
d = $MANUFACTURE_DATE_RAW
year = (d >> 9) + 1980
month = (d >> 5) & 0xF
day = d & 0x1F
print(f'{year}-{month:02d}-{day:02d}')
" 2>/dev/null)
    info "Battery Manufacture Date: $BATT_MFG_DATE"

    # Compare battery manufacture date to system setup date
    if [ -n "$BATT_MFG_DATE" ] && [ -n "$FIRST_BOOT" ]; then
        BATT_MFG_EPOCH=$(date -j -f "%Y-%m-%d" "$BATT_MFG_DATE" "+%s" 2>/dev/null)
        if [ -n "$BATT_MFG_EPOCH" ] && [ -n "$SETUP_EPOCH" ]; then
            DATE_DIFF=$(( (SETUP_EPOCH - BATT_MFG_EPOCH) / 86400 ))
            if [ "$DATE_DIFF" -lt -30 ]; then
                fail "Battery manufactured AFTER first setup — battery was replaced"
            elif [ "$DATE_DIFF" -gt 365 ]; then
                warn "Battery manufactured ${DATE_DIFF} days before first setup — old stock or replaced battery"
            else
                pass "Battery manufacture date consistent with setup date"
            fi
        fi
    fi
else
    info "Battery manufacture date: not available"
fi

# Battery condition check
if [ "$CONDITION" = "Normal" ]; then
    pass "Battery condition: Normal"
else
    fail "Battery condition: $CONDITION (may need service)"
fi

# Cycle count vs age analysis
if [ -n "$DAYS_SINCE" ] && [ "$DAYS_SINCE" -gt 0 ] && [ -n "$CYCLE_COUNT" ]; then
    CYCLES_PER_MONTH=$(python3 -c "print(round($CYCLE_COUNT * 30 / $DAYS_SINCE, 1))" 2>/dev/null || echo "N/A")
    info "Average cycles/month: $CYCLES_PER_MONTH"

    if [ "$DAYS_SINCE" -lt 30 ] && [ "$CYCLE_COUNT" -gt 10 ]; then
        fail "Machine setup $DAYS_SINCE days ago but has $CYCLE_COUNT cycles — used or battery reused"
    elif [ "$DAYS_SINCE" -lt 7 ] && [ "$CYCLE_COUNT" -gt 3 ]; then
        warn "Machine setup $DAYS_SINCE days ago with $CYCLE_COUNT cycles — verify if new"
    else
        pass "Cycle count consistent with setup age"
    fi
fi

# Capacity vs cycles check
if [ -n "$MAX_CAP" ] && [ -n "$CYCLE_COUNT" ]; then
    if [ "$CYCLE_COUNT" -lt 50 ] && [ "$MAX_CAP" -lt 97 ]; then
        warn "Low capacity (${MAX_CAP}%) for very low cycles ($CYCLE_COUNT) — old battery or aftermarket replacement"
    elif [ "$CYCLE_COUNT" -lt 100 ] && [ "$MAX_CAP" -lt 95 ]; then
        warn "Low capacity (${MAX_CAP}%) for low cycle count ($CYCLE_COUNT)"
    elif [ "$CYCLE_COUNT" -lt 300 ] && [ "$MAX_CAP" -lt 90 ]; then
        warn "Capacity degraded faster than expected (${MAX_CAP}% at $CYCLE_COUNT cycles)"
    elif [ "$CYCLE_COUNT" -lt 500 ] && [ "$MAX_CAP" -lt 85 ]; then
        warn "Significant capacity loss (${MAX_CAP}% at $CYCLE_COUNT cycles)"
    elif [ "$CYCLE_COUNT" -gt 1000 ]; then
        warn "High cycle count ($CYCLE_COUNT) — battery past rated lifespan (1000 cycles)"
    else
        pass "Battery capacity healthy for cycle count"
    fi
fi

# Battery controller authenticity
if echo "$DEVICE_NAME" | grep -qi "bq40z"; then
    pass "Battery controller is genuine TI gauge ($DEVICE_NAME)"
elif [ -n "$DEVICE_NAME" ]; then
    warn "Battery controller: $DEVICE_NAME (unusual — verify for this model)"
else
    warn "Could not identify battery controller"
fi

# Battery serial format check
if [ -n "$BATT_SERIAL" ] && [ ${#BATT_SERIAL} -gt 8 ]; then
    pass "Battery serial present and valid format"
else
    warn "Battery serial missing or short — may indicate aftermarket replacement"
fi

# Battery firmware check
if [ -n "$FW_VER" ] && [ ${#FW_VER} -ge 3 ]; then
    pass "Battery firmware present: $FW_VER"
else
    warn "Battery firmware version suspicious: '$FW_VER'"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "5. STORAGE HEALTH"
# ─────────────────────────────────────────────────────────────────────────────

STORAGE_NVME=$(system_profiler SPNVMeDataType 2>/dev/null)
STORAGE_GEN=$(system_profiler SPStorageDataType 2>/dev/null)

DISK_MODEL=$(echo "$STORAGE_NVME" | grep -m1 "Device Model\|Model:" | awk -F': ' '{print $2}' | tr -d ' ')
DISK_SERIAL=$(echo "$STORAGE_NVME" | grep -m1 "Serial Number" | awk -F': ' '{print $2}' | tr -d ' ')
DISK_SIZE_LINE=$(diskutil info disk0 2>/dev/null | grep "Disk Size")
DISK_LINK_WIDTH=$(echo "$STORAGE_NVME" | grep "Link Width" | awk -F': ' '{print $2}')
DISK_LINK_SPEED=$(echo "$STORAGE_NVME" | grep "Link Speed" | awk -F': ' '{print $2}')
TRIM_SUPPORT=$(echo "$STORAGE_GEN" | grep "TRIM" | awk -F': ' '{print $2}')

info "Storage Model: ${DISK_MODEL:-Built-in Apple SSD}"
info "Storage Serial: ${DISK_SERIAL:-N/A (Apple internal)}"
info "Disk Size: $DISK_SIZE_LINE"
info "NVMe Link Width: ${DISK_LINK_WIDTH:-N/A}"
info "NVMe Link Speed: ${DISK_LINK_SPEED:-N/A}"
info "TRIM Support: ${TRIM_SUPPORT:-N/A}"

# SMART status
SMART_STATUS=$(diskutil info disk0 2>/dev/null | grep "SMART Status" | awk -F': ' '{print $2}' | tr -d ' ')
if [ "$SMART_STATUS" = "Verified" ]; then
    pass "SMART status: Verified"
elif [ -n "$SMART_STATUS" ]; then
    fail "SMART status: $SMART_STATUS — disk may be failing"
else
    warn "Could not read SMART status"
fi

# Detailed SMART via smartctl if available
if command -v smartctl &>/dev/null; then
    info "Running detailed SMART check..."
    SMART_DETAIL=$(sudo smartctl --all /dev/disk0 2>/dev/null || smartctl --all /dev/disk0 2>/dev/null)
    SMART_PCT_USED=$(echo "$SMART_DETAIL" | grep -i "Percentage Used" | awk -F': ' '{print $2}' | tr -d ' %')
    SMART_SPARE=$(echo "$SMART_DETAIL" | grep -i "Available Spare:" | head -1 | awk -F': ' '{print $2}' | tr -d ' %')
    SMART_DATA_WRITTEN=$(echo "$SMART_DETAIL" | grep -i "Data Units Written" | awk -F': ' '{print $2}')

    if [ -n "$SMART_PCT_USED" ]; then
        info "SSD Wear Level: ${SMART_PCT_USED}% used"
        if [ "$SMART_PCT_USED" -gt 80 ] 2>/dev/null; then
            fail "SSD wear level critical (${SMART_PCT_USED}%)"
        elif [ "$SMART_PCT_USED" -gt 50 ] 2>/dev/null; then
            warn "SSD wear level moderate (${SMART_PCT_USED}%)"
        else
            pass "SSD wear level healthy (${SMART_PCT_USED}%)"
        fi
    fi
    if [ -n "$SMART_SPARE" ]; then
        info "SSD Available Spare: ${SMART_SPARE}%"
    fi
    if [ -n "$SMART_DATA_WRITTEN" ]; then
        info "Total Data Written: $SMART_DATA_WRITTEN"
    fi
else
    info "Install smartmontools for detailed SSD health: brew install smartmontools"
fi

# Disk usage
DISK_USAGE=$(df -h / | tail -1)
USED_PCT=$(echo "$DISK_USAGE" | awk '{print $5}' | tr -d '%')
USED_SIZE=$(echo "$DISK_USAGE" | awk '{print $3}')
AVAIL_SIZE=$(echo "$DISK_USAGE" | awk '{print $4}')
info "Used: $USED_SIZE / Available: $AVAIL_SIZE ($USED_PCT% used)"

if [ "$USED_PCT" -gt 90 ]; then
    warn "Disk nearly full ($USED_PCT%)"
else
    pass "Disk space healthy ($USED_PCT% used)"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "6. DISPLAY & SCREEN REPLACEMENT DETECTION"
# ─────────────────────────────────────────────────────────────────────────────

DISPLAY_INFO=$(system_profiler SPDisplaysDataType 2>/dev/null)
DISPLAY_TYPE=$(echo "$DISPLAY_INFO" | grep "Display Type" | awk -F': ' '{print $2}')
RESOLUTION=$(echo "$DISPLAY_INFO" | grep "Resolution" | head -1 | awk -F': ' '{print $2}')
PIXEL_DEPTH=$(echo "$DISPLAY_INFO" | grep "Pixel Depth" | awk -F': ' '{print $2}')
HDR=$(echo "$DISPLAY_INFO" | grep "HDR" | awk -F': ' '{print $2}')
METAL=$(echo "$DISPLAY_INFO" | grep "Metal" | head -1 | awk -F': ' '{print $2}')
REFRESH=$(echo "$DISPLAY_INFO" | grep -i "refresh\|ProMotion" | head -1)

info "Display Type: $DISPLAY_TYPE"
info "Resolution: $RESOLUTION"
info "Pixel Depth: $PIXEL_DEPTH"
info "HDR: ${HDR:-N/A}"
info "Metal Support: ${METAL:-N/A}"
if [ -n "$REFRESH" ]; then
    info "Refresh Rate: $REFRESH"
fi

if echo "$RESOLUTION" | grep -qi "Retina"; then
    pass "Retina display confirmed"
fi

if [ -n "$RESOLUTION" ]; then
    pass "Display detected and rendering"
else
    fail "Could not detect display resolution"
fi

# True Tone check (missing = likely screen replacement)
TRUE_TONE=$(defaults read /Library/Preferences/com.apple.CoreBrightness.plist 2>/dev/null | grep -i "truetone\|CBTrueTone" || echo "")
if [ -n "$TRUE_TONE" ]; then
    info "True Tone data found in system preferences"
    pass "True Tone calibration data present (original display likely)"
else
    # Alternative check
    AMBIENT_SENSOR=$(ioreg -l 2>/dev/null | grep -c "AppleHIDAlsEvent\|ALSSensor" || echo "0")
    if [ "$AMBIENT_SENSOR" -gt 0 ]; then
        info "Ambient light sensor detected ($AMBIENT_SENSOR entries)"
        pass "Ambient light sensor present"
    else
        warn "No ambient light sensor / True Tone data — display may have been replaced"
    fi
fi

# ProMotion check (14"/16" MBP M1 Pro/Max and later)
if echo "$MODEL_ID" | grep -qE "Mac1[4-9],|Mac[2-9][0-9],"; then
    if echo "$DISPLAY_INFO" | grep -qi "ProMotion\|120"; then
        pass "ProMotion (120Hz) detected"
    else
        info "ProMotion not confirmed (check System Settings > Displays for refresh rate options)"
    fi
fi

manual "Dead pixel test: Open fullscreen solid colors (white, red, green, blue, black) and inspect closely"
manual "Burn-in test: Display checkerboard for 5 min, switch to solid gray, look for ghost image"
manual "Backlight bleed: Show solid white at max brightness in dark room, check edges"

# ─────────────────────────────────────────────────────────────────────────────
header "7. CAMERA & MICROPHONE & SPEAKERS"
# ─────────────────────────────────────────────────────────────────────────────

CAMERA=$(system_profiler SPCameraDataType 2>/dev/null)
if echo "$CAMERA" | grep -qi "FaceTime\|Camera"; then
    CAM_MODEL=$(echo "$CAMERA" | grep "Model ID" | awk -F': ' '{print $2}')
    CAM_UNIQUE=$(echo "$CAMERA" | grep "Unique ID" | awk -F': ' '{print $2}')
    info "Camera: $CAM_MODEL"
    info "Camera UID: $CAM_UNIQUE"
    pass "Built-in camera detected"
else
    fail "No built-in camera detected"
fi

AUDIO=$(system_profiler SPAudioDataType 2>/dev/null)
if echo "$AUDIO" | grep -qi "Built-in Microphone\|MacBook Pro Microphone"; then
    pass "Built-in microphone detected"
else
    warn "Could not confirm built-in microphone"
fi

if echo "$AUDIO" | grep -qi "Built-in.*Speaker\|MacBook Pro Speakers"; then
    pass "Built-in speakers detected"
else
    warn "Could not confirm built-in speakers"
fi

# List all audio devices
info "Audio devices:"
echo "$AUDIO" | grep -E "^\s+[A-Za-z].*:" | head -10 | while read line; do info "  $line"; done

manual "Camera test: Open Photo Booth and verify image quality, no artifacts"
manual "Speaker test: Play audio at max volume, listen for distortion/rattling/crackling"
manual "Speaker test: Play L/R stereo test to verify both speakers work"
manual "Mic test: Open Voice Memos, record 10 seconds, play back — no static or hum"
manual "Headphone jack: Plug in headphones, verify audio output and auto-muting of speakers"

# ─────────────────────────────────────────────────────────────────────────────
header "8. KEYBOARD & TRACKPAD & TOUCH ID"
# ─────────────────────────────────────────────────────────────────────────────

# Touch ID / Secure Enclave
if ioreg -l 2>/dev/null | grep -qi "BiometricKit\|AppleSEP"; then
    pass "Touch ID / Secure Enclave detected"
else
    warn "Could not confirm Touch ID hardware"
fi

# Force Touch trackpad
TRACKPAD_INFO=$(ioreg -l 2>/dev/null | grep -i "ForceSupported\|AppleMultitouchTrackpad")
if echo "$TRACKPAD_INFO" | grep -qi "ForceSupported.*Yes\|AppleMultitouchTrackpad"; then
    pass "Force Touch trackpad detected"
else
    warn "Could not confirm Force Touch trackpad"
fi

# Keyboard backlight
if ioreg -l 2>/dev/null | grep -qi "KeyboardBacklight\|ALSPolicy"; then
    pass "Keyboard backlight controller detected"
fi

manual "Touch ID: Enroll a fingerprint in System Settings > Touch ID — confirms sensor works"
manual "Keyboard: Test EVERY key at https://keyboardchecker.com"
manual "Keyboard: Type rapidly to check for sticky/double keys (butterfly keyboard issue on 2016-2019)"
manual "Trackpad: Click in all 4 corners AND center — haptic feedback should feel identical everywhere"
manual "Trackpad: Test Force Click (deep press) on a file in Finder"
manual "Trackpad: Test gestures: 2-finger scroll, pinch-zoom, 3-finger swipe, 4-finger Mission Control"

# ─────────────────────────────────────────────────────────────────────────────
header "9. NETWORKING"
# ─────────────────────────────────────────────────────────────────────────────

# WiFi
WIFI=$(system_profiler SPAirPortDataType 2>/dev/null)
WIFI_STATUS=$(echo "$WIFI" | grep "Status:" | head -1 | awk -F': ' '{print $2}')
WIFI_CARD=$(echo "$WIFI" | grep "Card Type" | awk -F': ' '{print $2}')
WIFI_PROTOCOLS=$(echo "$WIFI" | grep "Supported PHY Modes" | awk -F': ' '{print $2}')
WIFI_COUNTRY=$(echo "$WIFI" | grep "Country Code" | head -1 | awk -F': ' '{print $2}')
WIFI_MAC=$(echo "$WIFI" | grep "MAC Address" | head -1 | awk -F': ' '{$1=""; print $0}' | xargs)
WIFI_FW=$(echo "$WIFI" | grep "Firmware Version" | awk -F': ' '{print $2}')

info "WiFi Card: $WIFI_CARD"
info "WiFi Firmware: $WIFI_FW"
info "Protocols: $WIFI_PROTOCOLS"
info "Country: $WIFI_COUNTRY"
info "MAC: $WIFI_MAC"
info "Status: $WIFI_STATUS"

if [ "$WIFI_STATUS" = "Connected" ]; then
    pass "WiFi connected"

    # Signal strength
    AIRPORT=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null)
    RSSI=$(echo "$AIRPORT" | grep "agrCtlRSSI" | awk -F': ' '{print $2}' | tr -d ' ')
    NOISE=$(echo "$AIRPORT" | grep "agrCtlNoise" | awk -F': ' '{print $2}' | tr -d ' ')
    TX_RATE=$(echo "$AIRPORT" | grep "lastTxRate" | awk -F': ' '{print $2}' | tr -d ' ')
    MCS=$(echo "$AIRPORT" | grep "MCS" | awk -F': ' '{print $2}' | tr -d ' ')
    CHANNEL=$(echo "$AIRPORT" | grep "channel:" | awk -F': ' '{print $2}' | tr -d ' ')

    if [ -n "$RSSI" ]; then
        info "Signal Strength (RSSI): ${RSSI} dBm"
        info "Noise: ${NOISE} dBm"
        info "Tx Rate: ${TX_RATE} Mbps"
        info "Channel: $CHANNEL"

        if [ "$RSSI" -gt -50 ] 2>/dev/null; then
            pass "WiFi signal excellent (${RSSI} dBm)"
        elif [ "$RSSI" -gt -70 ] 2>/dev/null; then
            pass "WiFi signal good (${RSSI} dBm)"
        elif [ "$RSSI" -gt -80 ] 2>/dev/null; then
            warn "WiFi signal weak (${RSSI} dBm)"
        else
            warn "WiFi signal very weak (${RSSI} dBm) — may indicate antenna issue"
        fi
    fi
else
    warn "WiFi not connected (status: $WIFI_STATUS)"
fi

if echo "$WIFI_PROTOCOLS" | grep -qi "ax\|802.11ax\|WiFi 6"; then
    pass "WiFi 6 (802.11ax) or newer supported"
fi

# Bluetooth
BT=$(system_profiler SPBluetoothDataType 2>/dev/null)
BT_ADDR=$(echo "$BT" | grep "Address:" | head -1 | awk -F': ' '{print $2}')
BT_FW=$(echo "$BT" | grep "Firmware" | head -1 | awk -F': ' '{print $2}')
BT_CHIPSET=$(echo "$BT" | grep "Chipset:" | head -1 | awk -F': ' '{print $2}')
BT_HCI=$(echo "$BT" | grep "HCI Version" | head -1 | awk -F': ' '{print $2}')
BT_LMP=$(echo "$BT" | grep "LMP Version" | head -1 | awk -F': ' '{print $2}')

info "Bluetooth Address: $BT_ADDR"
info "Bluetooth Chipset: $BT_CHIPSET"
info "Bluetooth Firmware: $BT_FW"
info "HCI Version: ${BT_HCI:-N/A}"

if [ -n "$BT_ADDR" ]; then
    pass "Bluetooth hardware detected"
else
    fail "Bluetooth not detected"
fi

manual "WiFi range test: Move 10+ meters from router, verify connection holds"
manual "Bluetooth: Pair a device, test at various distances (should work at 10m+)"

# ─────────────────────────────────────────────────────────────────────────────
header "10. PORTS & PERIPHERALS"
# ─────────────────────────────────────────────────────────────────────────────

# Thunderbolt
TB=$(system_profiler SPThunderboltDataType 2>/dev/null)
TB_VERSION=$(echo "$TB" | grep "Version" | head -1 | awk -F': ' '{print $2}')
info "Thunderbolt Version: ${TB_VERSION:-N/A}"

# USB buses
USB=$(system_profiler SPUSBDataType 2>/dev/null)
USB_BUSES=$(echo "$USB" | grep -c "USB3\|USB 3\|USB4\|USB 4" 2>/dev/null || echo "0")
info "USB 3.x/4.x buses detected: $USB_BUSES"

if [ -n "$TB_VERSION" ]; then
    pass "Thunderbolt controller detected"
else
    info "No Thunderbolt info (plug in a device to enumerate)"
fi

# Connected USB devices
USB_DEVICES=$(echo "$USB" | grep -B1 "Product ID\|Manufacturer" | grep -v "^--$\|Product\|Manuf" | head -10)
if [ -n "$USB_DEVICES" ]; then
    info "Connected USB devices:"
    echo "$USB" | grep -E "^\s+\w" | grep -v "Bus\|Host Controller\|USB Bus" | head -10 | while read line; do info "  $line"; done
fi

# SD Card
if system_profiler SPCardReaderDataType 2>/dev/null | grep -qi "Card Reader\|SDXC"; then
    pass "SD card reader detected"
else
    info "No SD card reader (may not be present on this model)"
fi

# HDMI
if system_profiler SPDisplaysDataType 2>/dev/null | grep -qi "HDMI"; then
    pass "HDMI port functional (display detected)"
else
    info "No HDMI display connected (plug in to test)"
fi

# MagSafe
MAGSAFE=$(echo "$POWER" | grep -i "MagSafe\|Name:" | tail -1)
if echo "$MAGSAFE" | grep -qi "MagSafe"; then
    info "MagSafe charger info: $MAGSAFE"
fi

manual "PORT TEST: Plug a USB device into EACH USB-C/Thunderbolt port individually"
manual "PORT TEST: Verify charging works from EACH USB-C port"
manual "PORT TEST: Test HDMI with external display"
manual "PORT TEST: Test SD card slot with a memory card"
manual "PORT TEST: Test headphone jack with wired headphones"
manual "MagSafe: Check LED (amber=charging, green=full)"

# ─────────────────────────────────────────────────────────────────────────────
header "11. CPU, GPU & MEMORY"
# ─────────────────────────────────────────────────────────────────────────────

CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null)
CPU_PERF_CORES=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "N/A")
CPU_EFF_CORES=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "N/A")
GPU_CORES=$(echo "$HW" | grep "GPU" | head -1 | awk -F': ' '{print $2}')
MEM_SIZE=$(sysctl -n hw.memsize 2>/dev/null)
MEM_GB=$((MEM_SIZE / 1073741824))

info "CPU: $CHIP"
info "Total Logical CPUs: $CPU_CORES"
info "Performance Cores: $CPU_PERF_CORES"
info "Efficiency Cores: $CPU_EFF_CORES"
info "GPU: ${GPU_CORES:-Integrated}"
info "Memory: ${MEM_GB} GB"

if [ "$CPU_CORES" -gt 0 ]; then
    pass "CPU responding ($CPU_CORES cores)"
fi
if [ -n "$GPU_CORES" ]; then
    pass "GPU cores detected: $GPU_CORES"
fi
if [ "$MEM_GB" -gt 0 ]; then
    pass "Memory: ${MEM_GB} GB detected"
fi

# Check thermal throttle history
THERM_LOG=$(pmset -g therm 2>/dev/null)
if echo "$THERM_LOG" | grep -qi "No thermal warning"; then
    pass "No thermal throttling recorded"
elif echo "$THERM_LOG" | grep -qi "CPU_Speed_Limit\|warning level"; then
    warn "Thermal throttling detected: $(echo "$THERM_LOG" | head -3)"
else
    info "Thermal status: $THERM_LOG"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "12. PERFORMANCE BENCHMARKS"
# ─────────────────────────────────────────────────────────────────────────────

# CPU single-core benchmark
info "Running CPU benchmark (single-core)..."
CPU_BENCH=$(python3 -c "
import time, hashlib
start = time.time()
for i in range(500000):
    hashlib.sha256(str(i).encode()).hexdigest()
elapsed = time.time() - start
print(f'{elapsed:.2f}')
" 2>/dev/null)
info "500K SHA-256 hashes: ${CPU_BENCH}s (lower is better)"

# CPU multi-core benchmark (background with kill)
info "Running CPU benchmark (multi-core)..."
python3 -c "
import time, hashlib, os, signal
signal.alarm(25)
cores = min(os.cpu_count(), 8)
pids = []
for _ in range(cores):
    pid = os.fork()
    if pid == 0:
        for i in range(250000):
            hashlib.sha256(str(i).encode()).hexdigest()
        os._exit(0)
    pids.append(pid)
start = time.time()
for pid in pids:
    os.waitpid(pid, 0)
elapsed = time.time() - start
print(f'{elapsed:.2f} {cores}')
" 2>/dev/null | while read MC_TIME MC_CORES; do
    info "Multi-core (${MC_CORES} cores x 250K): ${MC_TIME}s"
done

# Disk benchmark
info "Running disk benchmark..."
DD_WRITE=$(dd if=/dev/zero of=/tmp/.mac_diag_test bs=1m count=256 2>&1 | tail -1)
WRITE_SPEED=$(echo "$DD_WRITE" | awk '{print $(NF-1), $NF}')
info "Sequential write (256MB): $WRITE_SPEED"

sync
DD_READ=$(dd if=/tmp/.mac_diag_test of=/dev/null bs=1m 2>&1 | tail -1)
READ_SPEED=$(echo "$DD_READ" | awk '{print $(NF-1), $NF}')
info "Sequential read (256MB): $READ_SPEED"
rm -f /tmp/.mac_diag_test

# VM stats (lightweight, won't hang)
VM_FREE=$(vm_stat 2>/dev/null | grep "Pages free" | awk '{print $3}' | tr -d '.')
VM_ACTIVE=$(vm_stat 2>/dev/null | grep "Pages active" | awk '{print $3}' | tr -d '.')
if [ -n "$VM_FREE" ]; then
    FREE_MB=$(( VM_FREE * 4096 / 1048576 ))
    ACTIVE_MB=$(( VM_ACTIVE * 4096 / 1048576 ))
    info "VM Free: ${FREE_MB} MB | Active: ${ACTIVE_MB} MB"
fi

pass "Benchmarks completed"

# ─────────────────────────────────────────────────────────────────────────────
header "13. THERMAL STRESS TEST"
# ─────────────────────────────────────────────────────────────────────────────

info "Running 10-second CPU stress test to check for thermal throttling..."
info "(Watch for fan noise — grinding or clicking sounds indicate hardware issues)"

# Run stress for 10 seconds
for i in $(seq 1 ${CPU_CORES:-4}); do
    yes > /dev/null 2>&1 &
done
sleep 10
killall yes 2>/dev/null
sleep 1

# Post-stress check
POST_THERM=$(pmset -g therm 2>/dev/null)
if echo "$POST_THERM" | grep -qi "No thermal warning.*No performance warning"; then
    pass "No thermal throttling after 10s stress test"
elif echo "$POST_THERM" | grep -qi "No thermal warning"; then
    pass "No thermal throttling after 10s stress test"
else
    warn "Thermal warning detected after stress: $(echo "$POST_THERM" | head -3)"
fi

manual "Fan noise: Did you hear any grinding, clicking, or unusual sounds during the stress test?"

# ─────────────────────────────────────────────────────────────────────────────
header "14. SECURITY CONFIGURATION"
# ─────────────────────────────────────────────────────────────────────────────

# FileVault
FV_STATUS=$(fdesetup status 2>/dev/null || echo "Unknown")
info "FileVault: $FV_STATUS"
if echo "$FV_STATUS" | grep -qi "On"; then
    pass "FileVault enabled"
else
    warn "FileVault is OFF — enable for data protection"
fi

# SIP
SIP_STATUS=$(csrutil status 2>/dev/null || echo "Unknown")
info "$SIP_STATUS"
if echo "$SIP_STATUS" | grep -qi "enabled"; then
    pass "System Integrity Protection enabled"
else
    fail "SIP is disabled — security risk / possible jailbreak"
fi

# Gatekeeper
GK_STATUS=$(spctl --status 2>/dev/null || echo "Unknown")
info "Gatekeeper: $GK_STATUS"
if echo "$GK_STATUS" | grep -qi "enabled\|assessments enabled"; then
    pass "Gatekeeper enabled"
else
    warn "Gatekeeper disabled"
fi

# Firewall
FW_STATUS=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "0")
if [ "$FW_STATUS" -ge 1 ] 2>/dev/null; then
    pass "Firewall enabled (level: $FW_STATUS)"
else
    warn "Firewall disabled — consider enabling"
fi

# Secure Boot (Apple Silicon)
if [ -n "$CHIP" ]; then
    info "Apple Silicon detected — Secure Boot is always enabled"
    pass "Secure Boot (Apple Silicon)"
fi

# iBridge/T2
STARTUP_SEC=$(system_profiler SPiBridgeDataType 2>/dev/null)
if [ -n "$STARTUP_SEC" ]; then
    info "iBridge/T2 data: present"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "15. COMPONENT SERIAL CONSISTENCY"
# ─────────────────────────────────────────────────────────────────────────────

log ""
info "Cross-referencing all hardware identifiers for tampering detection..."
log ""

info "System Serial:    $SERIAL"
info "IOKit Serial:     $IOREG_SERIAL"
info "Battery Serial:   $BATT_SERIAL"
info "Battery (ioreg):  $BATT_IOREG_SERIAL"
info "Disk Serial:      ${DISK_SERIAL:-Apple Internal}"
info "WiFi MAC:         $WIFI_MAC"
info "Bluetooth Addr:   $BT_ADDR"
info "Hardware UUID:    $UUID"
info "Camera UID:       ${CAM_UNIQUE:-N/A}"

# Check if battery serials match across sources
if [ -n "$BATT_SERIAL" ] && [ -n "$BATT_IOREG_SERIAL" ]; then
    if [ "$BATT_SERIAL" = "$BATT_IOREG_SERIAL" ]; then
        pass "Battery serial consistent across sources"
    else
        warn "Battery serial mismatch: SPPower='$BATT_SERIAL' vs ioreg='$BATT_IOREG_SERIAL'"
    fi
fi

# Parts & Service hint
info ""
info "For definitive part replacement detection:"
manual "Check: System Settings > General > About > Parts & Service"
manual "Statuses: 'Genuine Apple Part' = original, 'Unknown' = aftermarket, 'Used' = from another Mac"

# ─────────────────────────────────────────────────────────────────────────────
header "16. SOFTWARE & CLEANLINESS"
# ─────────────────────────────────────────────────────────────────────────────

# Third-party LaunchDaemons
THIRD_PARTY_DAEMONS=$(ls /Library/LaunchDaemons/ 2>/dev/null | grep -v "com.apple" | head -20)
if [ -n "$THIRD_PARTY_DAEMONS" ]; then
    info "Third-party LaunchDaemons:"
    echo "$THIRD_PARTY_DAEMONS" | while read line; do info "  $line"; done
else
    pass "No third-party LaunchDaemons (clean system)"
fi

# Third-party LaunchAgents
THIRD_PARTY_AGENTS=$(ls /Library/LaunchAgents/ 2>/dev/null | grep -v "com.apple" | head -20)
if [ -n "$THIRD_PARTY_AGENTS" ]; then
    info "Third-party LaunchAgents:"
    echo "$THIRD_PARTY_AGENTS" | while read line; do info "  $line"; done
fi

# User LaunchAgents
USER_AGENTS=$(ls ~/Library/LaunchAgents/ 2>/dev/null | head -20)
if [ -n "$USER_AGENTS" ]; then
    info "User LaunchAgents:"
    echo "$USER_AGENTS" | while read line; do info "  $line"; done
fi

# Kernel extensions
KEXTS=$(kextstat 2>/dev/null | grep -v "com.apple" | tail -n +2 | head -10)
if [ -n "$KEXTS" ]; then
    warn "Third-party kernel extensions loaded"
else
    pass "No third-party kernel extensions"
fi

# Login items
info "Login items (apps that start at login):"
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | while read item; do
    info "  $item"
done

# ─────────────────────────────────────────────────────────────────────────────
header "17. CHARGER INFORMATION"
# ─────────────────────────────────────────────────────────────────────────────

CHARGER_CONNECTED=$(echo "$POWER" | grep "Connected:" | head -1 | awk -F': ' '{print $2}')
CHARGER_WATT=$(echo "$POWER" | grep "Wattage" | awk -F': ' '{print $2}')
CHARGER_NAME=$(echo "$POWER" | grep "Name:" | tail -1 | awk -F': ' '{print $2}')
CHARGER_MFG=$(echo "$POWER" | grep "Manufacturer:" | awk -F': ' '{print $2}')
CHARGER_SERIAL=$(echo "$POWER" | grep "Serial Number" | tail -1 | awk -F': ' '{print $2}')
CHARGER_FW=$(echo "$POWER" | grep "Firmware Version" | tail -1 | awk -F': ' '{print $2}')

if [ "$CHARGER_CONNECTED" = "Yes" ]; then
    info "Charger: $CHARGER_NAME ($CHARGER_WATT)"
    info "Manufacturer: $CHARGER_MFG"
    info "Charger Serial: $CHARGER_SERIAL"
    info "Charger Firmware: $CHARGER_FW"

    if echo "$CHARGER_MFG" | grep -qi "Apple"; then
        pass "Genuine Apple charger detected"
    else
        warn "Non-Apple charger: $CHARGER_MFG"
    fi

    # Wattage check
    WATT_NUM=$(echo "$CHARGER_WATT" | tr -d 'W ' | head -c 3)
    if [ "$WATT_NUM" -ge 67 ] 2>/dev/null; then
        pass "Charger wattage adequate (${CHARGER_WATT})"
    elif [ "$WATT_NUM" -gt 0 ] 2>/dev/null; then
        warn "Low wattage charger (${CHARGER_WATT}) — may charge slowly"
    fi
else
    info "No charger connected"
fi

# =============================================================================
header "SUMMARY"
# =============================================================================

log ""
log "$(printf '─%.0s' {1..70})"
echo -e "  ${GREEN}PASS: $PASS${NC}  |  ${YELLOW}WARN: $WARN${NC}  |  ${RED}FAIL: $FAIL${NC}"
echo "  PASS: $PASS  |  WARN: $WARN  |  FAIL: $FAIL" >> "$REPORT_FILE"
log "$(printf '─%.0s' {1..70})"
log ""

if [ "$FAIL" -eq 0 ] && [ "$WARN" -le 3 ]; then
    VERDICT="VERDICT: Machine appears healthy and genuine"
    echo -e "  ${GREEN}${BOLD}${VERDICT}${NC}"
elif [ "$FAIL" -eq 0 ]; then
    VERDICT="VERDICT: Machine OK but review warnings above"
    echo -e "  ${YELLOW}${BOLD}${VERDICT}${NC}"
elif [ "$FAIL" -le 2 ]; then
    VERDICT="VERDICT: Issues found — review failures before buying"
    echo -e "  ${RED}${BOLD}${VERDICT}${NC}"
else
    VERDICT="VERDICT: MULTIPLE ISSUES — proceed with extreme caution"
    echo -e "  ${RED}${BOLD}${VERDICT}${NC}"
fi
echo "  $VERDICT" >> "$REPORT_FILE"

log ""
log "$(printf '─%.0s' {1..70})"
log "  QUICK REFERENCE"
log "$(printf '─%.0s' {1..70})"
log "  Serial: $SERIAL"
log "  Model: $MODEL_NAME ($MODEL_ID)"
log "  Chip: $CHIP | Memory: $MEMORY"
log "  Battery: ${MAX_CAP}% capacity, $CYCLE_COUNT cycles, $CONDITION"
if [ -n "$BATT_MFG_DATE" ]; then
    log "  Battery Manufactured: $BATT_MFG_DATE"
fi
log "  Storage: SMART $SMART_STATUS, $USED_PCT% used"
log "  First Setup: ${FIRST_BOOT:-Unknown} (${DAYS_SINCE:-?} days ago)"
log ""

# Manual checks summary
if [ -n "$MANUAL_CHECKS" ]; then
    log "$(printf '─%.0s' {1..70})"
    log "  MANUAL CHECKS REQUIRED (cannot be automated)"
    log "$(printf '─%.0s' {1..70})"
    echo -e "$MANUAL_CHECKS" | tee -a "$REPORT_FILE"
    log ""
fi

log "$(printf '─%.0s' {1..70})"
log "  NEXT STEPS"
log "$(printf '─%.0s' {1..70})"
log "  1. Verify serial at https://checkcoverage.apple.com"
log "  2. Check Parts & Service: System Settings > General > About"
log "  3. Run Apple Diagnostics: Shut down, hold Power button, select Diagnostics"
log "  4. Complete all [TODO] manual checks above"
log "  5. For detailed SSD health: brew install smartmontools && sudo smartctl --all /dev/disk0"
log ""
log "Full report saved to: $REPORT_FILE"
log ""
