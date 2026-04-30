#!/usr/bin/env bash
# tirekicker v0.1.1 -- pre-purchase remote check
# https://github.com/C3T-Teknoloji-AS/tirekicker
# Read-only diagnostic. No installation. /tmp writes only.
# Privacy: SSH keys, browser data, user files are NEVER read.

set -uo pipefail

# ============================================================================
# CONFIG
# ============================================================================
TK_VERSION="0.1.5"
TK_SCHEMA_VERSION="0.1"
TK_TOTAL_STEPS=12

TK_WORKER_REPORT_URL="${TK_WORKER_REPORT_URL:-https://tk.ikizai.com/api/report}"
TK_WORKER_RELAY_URL="${TK_WORKER_RELAY_URL:-https://tk.ikizai.com/api/relay-url}"
TK_N8N_DIRECT_URL="${TK_N8N_DIRECT_URL:-}"
TK_HMAC_KEY="${TK_HMAC_KEY:-tk_v0_dev_unsafe}"

TK_DRY_RUN="${TK_DRY_RUN:-0}"
TK_REPORT_DIR="${TK_REPORT_DIR:-/tmp}"

# ============================================================================
# ARGS
# ============================================================================
for arg in "$@"; do
  case "$arg" in
    --dry-run) TK_DRY_RUN=1 ;;
    -v|--version) echo "tirekicker $TK_VERSION"; exit 0 ;;
    -h|--help)
      cat <<HELP
Usage: bash run.sh [--dry-run]

Options:
  --dry-run     Don't POST; print JSON to stdout, save to /tmp/.
  -v --version  Print version.
  -h --help     Print help.
HELP
      exit 0
      ;;
  esac
done

# ============================================================================
# COLORS / LOGGING
# ============================================================================
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_OK=$'\033[32m'; C_FAIL=$'\033[31m'; C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_OK=""; C_FAIL=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

TK_STEP=0
log_step() {
  TK_STEP=$((TK_STEP + 1))
  printf "[%d/%d] %s..." "$TK_STEP" "$TK_TOTAL_STEPS" "$1"
}
log_ok()    { printf " %sOK%s\n" "$C_OK" "$C_RESET"; }
log_skip()  { printf " %sskipped (%s)%s\n" "$C_DIM" "$1" "$C_RESET"; }
log_fail()  { printf " %sfailed (%s)%s\n" "$C_FAIL" "$1" "$C_RESET"; }

# ============================================================================
# HELPERS
# ============================================================================
gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    printf '%s-%04x-%04x-%04x-%012x' \
      "$(date +%s)" "$RANDOM" "$RANDOM" "$RANDOM" "$(( (RANDOM<<16) | RANDOM ))"
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $NF}'
  else
    echo "no_sha256"
  fi
}

hmac_sha256_hex() {
  local key="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 -hmac "$key" -hex 2>/dev/null | awk '{print $NF}'
  else
    sha256
  fi
}

json_string() {
  local s="${1:-}"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$s" | jq -Rsa .
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$s" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'
  else
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\b'/\\b}"
    s="${s//$'\f'/\\f}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '"%s"' "$s"
  fi
}

json_string_or_null() { [[ -z "${1:-}" ]] && printf 'null' || json_string "$1"; }

json_num_or_null() {
  local v="${1:-}"
  if [[ -z "$v" ]]; then printf 'null'
  elif [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then printf '%s' "$v"
  else printf 'null'
  fi
}

# Pipefail-safe count: ensure single integer
safe_count() {
  local val="${1:-0}"
  val=$(printf '%s' "$val" | head -1 | tr -d -c '0-9')
  [[ -z "$val" ]] && val=0
  printf '%s' "$val"
}

ERRORS_JSON=""
add_error() {
  local entry
  entry=$(printf '{"step":%s,"code":%s,"message":%s}' \
    "$(json_string "$1")" "$(json_string "$2")" "$(json_string "$3")")
  if [[ -z "$ERRORS_JSON" ]]; then ERRORS_JSON="$entry"
  else ERRORS_JSON="${ERRORS_JSON},${entry}"
  fi
}

read_file_safe() { [[ -r "$1" ]] && cat "$1" 2>/dev/null || true; }

sudo_run() {
  if [[ "${SUDO_OK:-false}" == "true" ]]; then
    sudo -n "$@" 2>/dev/null || true
  fi
}

# Parse "X MB/s" or "(X bytes/sec)" or "X bytes/sec" out of dd output -> MB/s
dd_mbps() {
  local out="$1"
  local v
  v=$(printf '%s' "$out" | grep -oE '[0-9.]+ MB/s' | awk '{print $1}' | head -1)
  if [[ -z "$v" ]]; then
    local bps
    bps=$(printf '%s' "$out" | grep -oE '[0-9]+ bytes/sec' | awk '{print $1}' | head -1)
    [[ -n "$bps" ]] && v=$(awk -v b="$bps" 'BEGIN{printf "%.1f", b/1048576}')
  fi
  printf '%s' "$v"
}

# ============================================================================
# BANNER + SUDO
# ============================================================================
clear 2>/dev/null || true
cat <<'BANNER'
========================================================
  Tirekicker  v0.1  -  Device Pre-Purchase Check
  ~85 seconds. Read-only. Privacy-safe.
========================================================

BANNER

SUDO_OK=false
echo "We need your device password once for full hardware access."
if sudo -v 2>/dev/null; then
  SUDO_OK=true
  ( while sudo -n true 2>/dev/null; do sleep 50; done ) &
  TK_SUDO_PID=$!
  trap '[[ -n "${TK_SUDO_PID:-}" ]] && kill "$TK_SUDO_PID" 2>/dev/null || true' EXIT
else
  echo "(continuing in limited mode -- some steps will report 'no_sudo')"
  add_error "sudo" "no_sudo" "sudo -v failed; some hardware data unavailable"
fi
echo

# ============================================================================
# STATE + SELF-CHECK
# ============================================================================
TK_RUN_ID="$(gen_uuid)"
TK_REPORT_FILE="${TK_REPORT_DIR}/tirekicker-${TK_RUN_ID}.json"
TK_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
TK_START_EPOCH="$(date +%s)"

JSON_OS="null"; JSON_SYSTEM="null"; JSON_HWID="null"; JSON_FRESHNESS="null"
JSON_GPU="null"; JSON_DMESG="null"; JSON_AI="null"; JSON_STORAGE="null"
JSON_SMART="null"; JSON_NET="null"; JSON_THERMAL="null"; JSON_FINGERPRINT="null"
THERMAL_SNAPSHOT_1=""

HAVE_JQ=$(command -v jq >/dev/null 2>&1 && echo true || echo false)
HAVE_PY=$(command -v python3 >/dev/null 2>&1 && echo true || echo false)
HAVE_NVSMI=$(command -v nvidia-smi >/dev/null 2>&1 && echo true || echo false)
HAVE_NVME=$(command -v nvme >/dev/null 2>&1 && echo true || echo false)
HAVE_DMI=$(command -v dmidecode >/dev/null 2>&1 && echo true || echo false)
HAVE_LSPCI=$(command -v lspci >/dev/null 2>&1 && echo true || echo false)
HAVE_OPENSSL=$(command -v openssl >/dev/null 2>&1 && echo true || echo false)
HAVE_CURL=$(command -v curl >/dev/null 2>&1 && echo true || echo false)
HAVE_IP=$(command -v ip >/dev/null 2>&1 && echo true || echo false)
HAVE_IFCONFIG=$(command -v ifconfig >/dev/null 2>&1 && echo true || echo false)
HAVE_SYSCTL=$(command -v sysctl >/dev/null 2>&1 && echo true || echo false)

log_step "Self-check"
log_ok

# ============================================================================
# STEP 1: OS + arch
# ============================================================================
log_step "Detecting OS"
RAW_UNAME="$(uname -a 2>/dev/null || echo '')"
ARCH="$(uname -m 2>/dev/null || echo '')"
KERNEL="$(uname -r 2>/dev/null || echo '')"
RAW_OSREL="$(read_file_safe /etc/os-release)"
OS_NAME=""; OS_VER=""; OS_PRETTY=""
if [[ -n "$RAW_OSREL" ]]; then
  OS_NAME=$(echo "$RAW_OSREL" | awk -F= '/^NAME=/{gsub(/"/,"",$2); print $2; exit}')
  OS_VER=$(echo "$RAW_OSREL" | awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2; exit}')
  OS_PRETTY=$(echo "$RAW_OSREL" | awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2; exit}')
fi
if [[ -z "$OS_NAME" ]] && command -v sw_vers >/dev/null 2>&1; then
  OS_NAME="macOS"
  OS_VER=$(sw_vers -productVersion 2>/dev/null || echo '')
  OS_PRETTY="macOS $OS_VER"
fi
JSON_OS=$(printf '{"kernel":%s,"name":%s,"version":%s,"pretty_name":%s,"arch":%s,"raw_uname_a":%s,"raw_os_release":%s}' \
  "$(json_string_or_null "$KERNEL")" \
  "$(json_string_or_null "$OS_NAME")" \
  "$(json_string_or_null "$OS_VER")" \
  "$(json_string_or_null "$OS_PRETTY")" \
  "$(json_string_or_null "$ARCH")" \
  "$(json_string_or_null "$RAW_UNAME")" \
  "$(json_string_or_null "$RAW_OSREL")")
log_ok

# ============================================================================
# STEP 2: System info (CPU, RAM, disks, board) -- Linux + Mac fallbacks
# ============================================================================
log_step "Reading hardware info"
CPU_MODEL=""; CPU_LOG=""; CPU_PHYS=""; CPU_MHZ=""
RAW_LSCPU=""; RAW_MEMINFO=""; RAW_DMI_MEM=""; RAW_DMI_SYS=""
RAM_TOTAL=""; RAM_AVAIL=""; RAM_TYPE=""; RAM_SPEED=""
BOARD_MFR=""; BOARD_PRD=""; BOARD_SH=""; BIOS_VER=""; BIOS_DATE=""

# CPU -- Linux first
if command -v lscpu >/dev/null 2>&1; then
  RAW_LSCPU="$(lscpu 2>/dev/null || true)"
  CPU_MODEL=$(echo "$RAW_LSCPU" | awk -F: '/^Model name/{sub(/^ +/,"",$2); print $2; exit}')
  CPU_LOG=$(nproc 2>/dev/null || echo '')
  CPU_PHYS=$(echo "$RAW_LSCPU" | awk -F: '/^Core\(s\) per socket/{gsub(/ /,"",$2); print $2; exit}')
  CPU_MHZ=$(echo "$RAW_LSCPU" | awk -F: '/^CPU max MHz/{gsub(/ /,"",$2); print $2; exit}')
fi
if [[ -z "$CPU_MODEL" ]] && [[ -r /proc/cpuinfo ]]; then
  CPU_MODEL=$(awk -F: '/model name|Model/{sub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo)
  [[ -z "$CPU_LOG" ]] && CPU_LOG=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo '')
fi
# Mac fallback via sysctl
if [[ -z "$CPU_MODEL" ]] && [[ "$HAVE_SYSCTL" == "true" ]]; then
  CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo '')
  [[ -z "$CPU_LOG" ]]  && CPU_LOG=$(sysctl -n hw.logicalcpu 2>/dev/null || echo '')
  [[ -z "$CPU_PHYS" ]] && CPU_PHYS=$(sysctl -n hw.physicalcpu 2>/dev/null || echo '')
fi

# RAM -- Linux meminfo first
RAW_MEMINFO="$(read_file_safe /proc/meminfo)"
if [[ -n "$RAW_MEMINFO" ]]; then
  KB=$(echo "$RAW_MEMINFO" | awk '/^MemTotal:/{print $2}')
  [[ -n "$KB" ]] && RAM_TOTAL=$((KB * 1024))
  KB=$(echo "$RAW_MEMINFO" | awk '/^MemAvailable:/{print $2}')
  [[ -n "$KB" ]] && RAM_AVAIL=$((KB * 1024))
fi
# Mac fallback
if [[ -z "$RAM_TOTAL" ]] && [[ "$HAVE_SYSCTL" == "true" ]]; then
  RAM_TOTAL=$(sysctl -n hw.memsize 2>/dev/null || echo '')
fi

# RAM type/speed via dmidecode (Linux + sudo)
if [[ "$SUDO_OK" == "true" ]] && [[ "$HAVE_DMI" == "true" ]]; then
  RAW_DMI_MEM="$(sudo_run dmidecode -t memory)"
  RAM_TYPE=$(echo "$RAW_DMI_MEM" | awk -F: '/^[[:space:]]*Type:/{sub(/^ +/,"",$2); if ($2 != "Unknown" && $2 != "") {print $2; exit}}')
  RAM_SPEED=$(echo "$RAW_DMI_MEM" | awk -F: '/^[[:space:]]*Configured Memory Speed:/{gsub(/[^0-9]/,"",$2); if($2!="") {print $2; exit}}')
  [[ -z "$RAM_SPEED" ]] && RAM_SPEED=$(echo "$RAW_DMI_MEM" | awk -F: '/^[[:space:]]*Speed:/{gsub(/[^0-9]/,"",$2); if($2!="") {print $2; exit}}')
  RAW_DMI_SYS="$(sudo_run dmidecode -t system)"
  if [[ -n "$RAW_DMI_SYS" ]]; then
    BOARD_MFR=$(echo "$RAW_DMI_SYS" | awk -F: '/^[[:space:]]*Manufacturer:/{sub(/^ +/,"",$2); print $2; exit}')
    BOARD_PRD=$(echo "$RAW_DMI_SYS" | awk -F: '/^[[:space:]]*Product Name:/{sub(/^ +/,"",$2); print $2; exit}')
    BOARD_SER=$(echo "$RAW_DMI_SYS" | awk -F: '/^[[:space:]]*Serial Number:/{sub(/^ +/,"",$2); print $2; exit}')
    if [[ -n "$BOARD_SER" && "$BOARD_SER" != "Not Specified" ]]; then
      BOARD_SH="sha256:$(printf '%s' "$BOARD_SER" | sha256)"
    fi
    BIOS_VER=$(sudo_run dmidecode -s bios-version)
    BIOS_DATE=$(sudo_run dmidecode -s bios-release-date)
  fi
fi
# Mac board info (best effort)
if [[ -z "$BOARD_PRD" ]] && command -v system_profiler >/dev/null 2>&1; then
  SP_HW=$(system_profiler SPHardwareDataType 2>/dev/null || true)
  BOARD_MFR=$(echo "$SP_HW" | awk -F: '/Model Identifier/{sub(/^ +/,"",$2); print $2; exit}')
  BOARD_PRD="$BOARD_MFR"
  BOARD_SER_RAW=$(echo "$SP_HW" | awk -F: '/Serial Number/{sub(/^ +/,"",$2); print $2; exit}')
  if [[ -n "$BOARD_SER_RAW" ]]; then
    BOARD_SH="sha256:$(printf '%s' "$BOARD_SER_RAW" | sha256)"
  fi
fi

# Disks -- Linux
DISKS_JSON="[]"
if command -v lsblk >/dev/null 2>&1 && [[ "$HAVE_JQ" == "true" ]]; then
  DISKS_JSON=$(lsblk -d -b -o NAME,SIZE,MODEL,TRAN,SERIAL --json 2>/dev/null \
    | jq '[.blockdevices[] | select(.tran != null and .tran != "") | {name:.name, size_bytes:(.size|tonumber? // 0), model:(.model//""), tran:(.tran//"")}]' 2>/dev/null || echo '[]')
  [[ -z "$DISKS_JSON" ]] && DISKS_JSON="[]"
fi
# Disks -- Mac fallback (root disk only, basic)
if [[ "$DISKS_JSON" == "[]" ]] && command -v df >/dev/null 2>&1 && command -v diskutil >/dev/null 2>&1; then
  ROOT_DEV=$(df / 2>/dev/null | awk 'NR==2{print $1}')
  ROOT_SIZE=$(df -k / 2>/dev/null | awk 'NR==2{print $2 * 1024}')
  if [[ -n "$ROOT_DEV" && -n "$ROOT_SIZE" ]]; then
    DISKS_JSON=$(printf '[{"name":%s,"size_bytes":%s,"model":"","tran":"unknown"}]' \
      "$(json_string "$ROOT_DEV")" "$ROOT_SIZE")
  fi
fi

# Filesystem usage on /
FS_TOT=""; FS_FREE=""; FS_PCT=""
if command -v df >/dev/null 2>&1; then
  if df -B1 / >/dev/null 2>&1; then
    DFLINE=$(df -B1 / 2>/dev/null | awk 'NR==2{print $2,$4,$5}')
  else
    # Mac df -k
    DFLINE=$(df -k / 2>/dev/null | awk 'NR==2{print $2*1024,$4*1024,$5}')
  fi
  FS_TOT=$(echo "$DFLINE" | awk '{print $1}')
  FS_FREE=$(echo "$DFLINE" | awk '{print $2}')
  FS_PCT=$(echo "$DFLINE" | awk '{gsub(/%/,"",$3); print $3}')
fi

JSON_SYSTEM=$(printf '{"cpu":{"model":%s,"arch":%s,"cores_logical":%s,"cores_physical":%s,"max_mhz":%s,"raw_lscpu":%s},"ram":{"total_bytes":%s,"available_bytes":%s,"type":%s,"speed_mts":%s,"raw_meminfo":%s,"raw_dmidecode_memory":%s},"disks":%s,"filesystem":{"mountpoint":"/","total_bytes":%s,"free_bytes":%s,"used_pct":%s},"board":{"manufacturer":%s,"product":%s,"serial_hash":%s,"bios_version":%s,"bios_date":%s,"raw_dmidecode_system":%s}}' \
  "$(json_string_or_null "$CPU_MODEL")" \
  "$(json_string_or_null "$ARCH")" \
  "$(json_num_or_null "$CPU_LOG")" \
  "$(json_num_or_null "$CPU_PHYS")" \
  "$(json_num_or_null "$CPU_MHZ")" \
  "$(json_string_or_null "$RAW_LSCPU")" \
  "$(json_num_or_null "$RAM_TOTAL")" \
  "$(json_num_or_null "$RAM_AVAIL")" \
  "$(json_string_or_null "$RAM_TYPE")" \
  "$(json_num_or_null "$RAM_SPEED")" \
  "$(json_string_or_null "$RAW_MEMINFO")" \
  "$(json_string_or_null "$RAW_DMI_MEM")" \
  "$DISKS_JSON" \
  "$(json_num_or_null "$FS_TOT")" \
  "$(json_num_or_null "$FS_FREE")" \
  "$(json_num_or_null "$FS_PCT")" \
  "$(json_string_or_null "$BOARD_MFR")" \
  "$(json_string_or_null "$BOARD_PRD")" \
  "$(json_string_or_null "$BOARD_SH")" \
  "$(json_string_or_null "$BIOS_VER")" \
  "$(json_string_or_null "$BIOS_DATE")" \
  "$(json_string_or_null "$RAW_DMI_SYS")")
log_ok

# ============================================================================
# STEP 3: Hardware ID cross-check
# ============================================================================
log_step "Hardware ID cross-check"
GPU_NAME_NS=""; GPU_PCI_DEV_ID=""; GPU_PCI_NAME=""; RAW_LSPCI_GPU=""
if [[ "$HAVE_NVSMI" == "true" ]]; then
  GPU_NAME_NS="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs)"
fi
if [[ "$HAVE_LSPCI" == "true" ]]; then
  RAW_LSPCI_GPU="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display|nvidia' || true)"
  GPU_PCI_NAME="$(echo "$RAW_LSPCI_GPU" | head -1 | sed 's/^[^ ]* //; s/[[:space:]]*$//')"
  GPU_PCI_DEV_ID="$(echo "$RAW_LSPCI_GPU" | head -1 | grep -oE '\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]' | head -1)"
fi
HWID_MISMATCH="false"
HWID_REASONS=()
if [[ -n "$GPU_NAME_NS" && -n "$GPU_PCI_NAME" ]]; then
  if ! echo "$GPU_PCI_NAME" | grep -qi nvidia; then
    HWID_MISMATCH="true"
    HWID_REASONS+=("nvidia-smi reports GPU but lspci shows no NVIDIA device")
  fi
elif [[ -n "$GPU_NAME_NS" && -z "$GPU_PCI_NAME" ]]; then
  HWID_MISMATCH="true"
  HWID_REASONS+=("nvidia-smi has GPU but lspci returned nothing")
fi
HWID_REASONS_JSON="[]"
if [[ ${#HWID_REASONS[@]} -gt 0 ]]; then
  HWID_REASONS_JSON="["
  for i in "${!HWID_REASONS[@]}"; do
    [[ $i -gt 0 ]] && HWID_REASONS_JSON="${HWID_REASONS_JSON},"
    HWID_REASONS_JSON="${HWID_REASONS_JSON}$(json_string "${HWID_REASONS[$i]}")"
  done
  HWID_REASONS_JSON="${HWID_REASONS_JSON}]"
fi
JSON_HWID=$(printf '{"gpu_name_nvidia_smi":%s,"gpu_pci_device_id":%s,"gpu_pci_name":%s,"hwid_mismatch":%s,"reasons":%s,"raw_lspci_gpu":%s}' \
  "$(json_string_or_null "$GPU_NAME_NS")" \
  "$(json_string_or_null "$GPU_PCI_DEV_ID")" \
  "$(json_string_or_null "$GPU_PCI_NAME")" \
  "$HWID_MISMATCH" \
  "$HWID_REASONS_JSON" \
  "$(json_string_or_null "$RAW_LSPCI_GPU")")
log_ok

# ============================================================================
# STEP 4: Freshness / tamper signals
# ============================================================================
log_step "Reading freshness signals"
UPTIME_SEC=""
BOOT_EPOCH=""
[[ -r /proc/uptime ]] && UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime)
if [[ -z "$UPTIME_SEC" ]] && [[ "$HAVE_SYSCTL" == "true" ]]; then
  # Mac kern.boottime: "{ sec = N, usec = M } ..."
  # grep matches "sec = X" inside "usec = X" too -- head -1 picks first.
  BOOT_EPOCH=$(sysctl -n kern.boottime 2>/dev/null | grep -oE 'sec = [0-9]+' | head -1 | awk '{print $3}')
  [[ -n "$BOOT_EPOCH" ]] && UPTIME_SEC=$(( $(date +%s) - BOOT_EPOCH ))
fi

BOOT_TIME=""
if command -v uptime >/dev/null 2>&1; then
  BOOT_TIME=$(uptime -s 2>/dev/null || true)
fi
if [[ -z "$BOOT_TIME" ]] && [[ -n "$BOOT_EPOCH" ]]; then
  BOOT_TIME=$(date -u -r "$BOOT_EPOCH" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo '')
fi
if [[ -z "$BOOT_TIME" ]] && command -v who >/dev/null 2>&1; then
  BOOT_TIME=$(who -b 2>/dev/null | awk '{$1=""; sub(/^ +/,""); print}' | head -1)
fi

OS_INSTALL=""
if [[ -e /etc/hostname ]] && command -v stat >/dev/null 2>&1; then
  OS_INSTALL=$(stat -c %w /etc/hostname 2>/dev/null | head -1)
  [[ "$OS_INSTALL" == "-" ]] && OS_INSTALL=""
fi

PKG_COUNT=""
if command -v dpkg >/dev/null 2>&1; then
  PKG_COUNT=$(dpkg -l 2>/dev/null | grep -c '^ii' 2>/dev/null)
  PKG_COUNT=$(safe_count "$PKG_COUNT")
elif command -v rpm >/dev/null 2>&1; then
  PKG_COUNT=$(rpm -qa 2>/dev/null | wc -l 2>/dev/null)
  PKG_COUNT=$(safe_count "$PKG_COUNT")
fi

JOURNAL_LINES_24H=""
if command -v journalctl >/dev/null 2>&1; then
  JOURNAL_LINES_24H=$(sudo_run journalctl --since "24 hours ago" --no-pager 2>/dev/null | wc -l 2>/dev/null)
  JOURNAL_LINES_24H=$(safe_count "$JOURNAL_LINES_24H")
fi

LAST_LOGIN_7D=""
if command -v last >/dev/null 2>&1; then
  LAST_LOGIN_7D=$(last -s -7days 2>/dev/null | grep -cE '^[a-zA-Z]' 2>/dev/null)
  LAST_LOGIN_7D=$(safe_count "$LAST_LOGIN_7D")
fi

RAW_WHO_B="$(who -b 2>/dev/null || true)"
RAW_LAST_HEAD="$(last 2>/dev/null | head -20 || true)"

JSON_FRESHNESS=$(printf '{"uptime_sec":%s,"boot_time":%s,"os_install_time":%s,"installed_packages_count":%s,"journal_lines_24h":%s,"last_login_count_7d":%s,"raw_who_b":%s,"raw_last_head":%s}' \
  "$(json_num_or_null "$UPTIME_SEC")" \
  "$(json_string_or_null "$BOOT_TIME")" \
  "$(json_string_or_null "$OS_INSTALL")" \
  "$(json_num_or_null "$PKG_COUNT")" \
  "$(json_num_or_null "$JOURNAL_LINES_24H")" \
  "$(json_num_or_null "$LAST_LOGIN_7D")" \
  "$(json_string_or_null "$RAW_WHO_B")" \
  "$(json_string_or_null "$RAW_LAST_HEAD")")
log_ok

# ============================================================================
# STEP 5: GPU + stack + topology
# ============================================================================
log_step "Reading GPU + stack"
RAW_NVSMI_Q=""
GPU_DETECTED="false"
GPU_DEVICES_JSON="[]"
STACK_JSON="null"
RAW_TOPO=""

if [[ "$HAVE_NVSMI" == "true" ]]; then
  GPU_DETECTED="true"
  RAW_NVSMI_Q="$(nvidia-smi -q 2>/dev/null || true)"
  RAW_TOPO="$(nvidia-smi topo -m 2>/dev/null || true)"

  DEVS=""
  while IFS=',' read -r idx name uuid mem_total mem_used drv_ver pstate ecc; do
    [[ -z "$idx" ]] && continue
    idx=$(echo "$idx" | xargs); name=$(echo "$name" | xargs); uuid=$(echo "$uuid" | xargs)
    mem_total_b=""; mem_used_b=""
    if [[ "$mem_total" =~ MiB ]]; then
      mem_total_b=$(echo "$mem_total" | awk '{print int($1 * 1024 * 1024)}')
    fi
    if [[ "$mem_used" =~ MiB ]]; then
      mem_used_b=$(echo "$mem_used" | awk '{print int($1 * 1024 * 1024)}')
    fi
    uuid_h=""
    [[ -n "$uuid" ]] && uuid_h="sha256:$(printf '%s' "$uuid" | sha256)"
    drv_ver=$(echo "$drv_ver" | xargs); pstate=$(echo "$pstate" | xargs); ecc=$(echo "$ecc" | xargs)
    ecc_bool="false"
    [[ "$ecc" =~ Enabled ]] && ecc_bool="true"
    DEV=$(printf '{"index":%s,"name":%s,"uuid_hash":%s,"memory_total_bytes":%s,"memory_used_bytes":%s,"driver_version":%s,"pstate":%s,"ecc_enabled":%s}' \
      "$(json_num_or_null "$idx")" \
      "$(json_string_or_null "$name")" \
      "$(json_string_or_null "$uuid_h")" \
      "$(json_num_or_null "$mem_total_b")" \
      "$(json_num_or_null "$mem_used_b")" \
      "$(json_string_or_null "$drv_ver")" \
      "$(json_string_or_null "$pstate")" \
      "$ecc_bool")
    DEVS="${DEVS:+${DEVS},}${DEV}"
  done < <(nvidia-smi --query-gpu=index,name,uuid,memory.total,memory.used,driver_version,pstate,ecc.mode.current --format=csv,noheader 2>/dev/null)
  GPU_DEVICES_JSON="[${DEVS}]"

  CUDA_VER=""
  if command -v nvcc >/dev/null 2>&1; then
    CUDA_VER=$(nvcc --version 2>/dev/null | grep -oE 'release [0-9.]+' | awk '{print $2}')
  fi
  [[ -z "$CUDA_VER" ]] && CUDA_VER=$(echo "$RAW_NVSMI_Q" | awk -F: '/CUDA Version/{gsub(/ /,"",$2); print $2; exit}')
  DRV_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | xargs)
  CUDNN_VER=""
  if [[ -r /usr/include/cudnn_version.h ]]; then
    CUDNN_VER=$(awk '/CUDNN_MAJOR/{maj=$3} /CUDNN_MINOR/{min=$3} /CUDNN_PATCHLEVEL/{pat=$3} END{print maj"."min"."pat}' /usr/include/cudnn_version.h 2>/dev/null)
  fi
  PT_VER=""; PT_CUDA="false"
  if [[ "$HAVE_PY" == "true" ]]; then
    PT_OUT=$(python3 -c 'import torch; print(torch.__version__); print("yes" if torch.cuda.is_available() else "no")' 2>/dev/null || echo '')
    PT_VER=$(echo "$PT_OUT" | sed -n '1p')
    [[ "$(echo "$PT_OUT" | sed -n '2p')" == "yes" ]] && PT_CUDA="true"
  fi
  RAW_NVLINK=$(nvidia-smi nvlink -s 2>/dev/null || true)
  RAW_RETIRED=$(nvidia-smi --query-retired-pages=gpu_uuid,retired_pages.address,retired_pages.cause --format=csv,noheader 2>/dev/null || true)

  STACK_JSON=$(printf '{"driver_version":%s,"cuda_version":%s,"cudnn_version":%s,"pytorch_version":%s,"pytorch_cuda_available":%s,"raw_nvlink_status":%s,"raw_retired_pages":%s}' \
    "$(json_string_or_null "$DRV_VER")" \
    "$(json_string_or_null "$CUDA_VER")" \
    "$(json_string_or_null "$CUDNN_VER")" \
    "$(json_string_or_null "$PT_VER")" \
    "$PT_CUDA" \
    "$(json_string_or_null "$RAW_NVLINK")" \
    "$(json_string_or_null "$RAW_RETIRED")")
fi

JSON_GPU=$(printf '{"detected":%s,"devices":%s,"stack":%s,"topology":%s,"raw_nvidia_smi_q":%s}' \
  "$GPU_DETECTED" \
  "$GPU_DEVICES_JSON" \
  "$STACK_JSON" \
  "$(json_string_or_null "$RAW_TOPO")" \
  "$(json_string_or_null "$RAW_NVSMI_Q")")
log_ok

# ============================================================================
# STEP 6: dmesg history scan -- pipefail-safe counting
# ============================================================================
log_step "Scanning dmesg history"
RAW_DMESG_ERR=""
if [[ "$SUDO_OK" == "true" ]]; then
  RAW_DMESG_ERR="$(sudo_run dmesg -T --level=err,crit,alert,emerg 2>/dev/null | tail -200)"
fi
[[ -z "$RAW_DMESG_ERR" ]] && RAW_DMESG_ERR="$(dmesg -T 2>/dev/null | grep -iE 'error|fail|warn|MCE|machine check|fallen off|nvrm:' | tail -200 || true)"

PAT_NAMES=("MCE" "machine_check" "PCIe_error" "GPU_fallen_off" "NVRM_xid" "ECC_error" "thermal_throttle")
PAT_REGEX=("MCE|mce" "machine[_ ]check" "PCIe.*error|AER.*error" "fallen off the bus" "NVRM:.*Xid|NVRM:.*error" "ecc.*error|ECC.*error" "thermal.*throttl|HW Slowdown")
HITS=""
for i in "${!PAT_NAMES[@]}"; do
  RAW_COUNT=$(printf '%s\n' "$RAW_DMESG_ERR" | grep -c -iE "${PAT_REGEX[$i]}" 2>/dev/null)
  COUNT=$(safe_count "$RAW_COUNT")
  SAMPLE=$(printf '%s\n' "$RAW_DMESG_ERR" | grep -iE "${PAT_REGEX[$i]}" 2>/dev/null | head -1)
  HIT=$(printf '{"pattern":%s,"count":%s,"sample":%s}' \
    "$(json_string "${PAT_NAMES[$i]}")" \
    "$COUNT" \
    "$(json_string_or_null "$SAMPLE")")
  HITS="${HITS:+${HITS},}${HIT}"
done
JSON_DMESG=$(printf '{"pattern_hits":[%s],"raw_err_tail":%s}' \
  "$HITS" \
  "$(json_string_or_null "$RAW_DMESG_ERR")")
log_ok

# ============================================================================
# STEP 7 + 8 + (THERMAL SNAPSHOT 1): AI smoke + parallel storage bench
# ============================================================================
log_step "Running sustained AI smoke + storage bench (60s)"

# Background storage bench at smoke -5s
(
  sleep 55
  BENCH_FILE="${TK_REPORT_DIR}/tk_bench_$$"
  BENCH_SIZE_MB=2048
  BENCH_START=$(date +%s)
  # Linux dd uses oflag=direct; Mac BSD dd does not support oflag, but accepts simpler flags
  if dd if=/dev/zero of="$BENCH_FILE" bs=1m count=$BENCH_SIZE_MB 2>/dev/null >/dev/null; then
    rm -f "$BENCH_FILE"
    DD_OUT_W=$(dd if=/dev/zero of="$BENCH_FILE" bs=1m count=$BENCH_SIZE_MB 2>&1 | tail -1)
    DD_OUT_R=$(dd if="$BENCH_FILE" of=/dev/null bs=1m 2>&1 | tail -1)
  else
    DD_OUT_W=$(dd if=/dev/zero of="$BENCH_FILE" bs=1M count=$BENCH_SIZE_MB oflag=direct 2>&1 | tail -1)
    DD_OUT_R=$(dd if="$BENCH_FILE" of=/dev/null bs=1M iflag=direct 2>&1 | tail -1)
  fi
  WRITE_MBPS=$(dd_mbps "$DD_OUT_W")
  READ_MBPS=$(dd_mbps "$DD_OUT_R")
  BENCH_DUR=$(( $(date +%s) - BENCH_START ))
  rm -f "$BENCH_FILE" 2>/dev/null

  WMB_J="null"; RMB_J="null"
  [[ -n "$WRITE_MBPS" ]] && WMB_J="$WRITE_MBPS"
  [[ -n "$READ_MBPS" ]] && RMB_J="$READ_MBPS"
  printf '{"device_path":"%s","test_size_mb":%d,"write_mbps":%s,"read_mbps":%s,"duration_sec":%d,"raw_dd_write":%s,"raw_dd_read":%s}' \
    "$TK_REPORT_DIR" "$BENCH_SIZE_MB" "$WMB_J" "$RMB_J" "$BENCH_DUR" \
    "$(printf '%s' "$DD_OUT_W" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" \
    "$(printf '%s' "$DD_OUT_R" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" \
    > "${TK_REPORT_DIR}/tk_bench_result_$$"
) &
BENCH_PID=$!

# Background thermal snapshot 1 at smoke 30s
(
  sleep 30
  if [[ "$HAVE_NVSMI" == "true" ]]; then
    nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.gr,clocks.mem,pstate --format=csv,noheader 2>/dev/null | head -1 \
      > "${TK_REPORT_DIR}/tk_thermal1_$$"
  fi
) &
THERMAL1_PID=$!

# AI smoke -- clean try-chain: torch_cuda -> numpy -> error
SMOKE_START=$(date +%s)
SMOKE_BACKEND="skipped"
SMOKE_PEAK_GFLOPS=""
SMOKE_PEAK_MEM_BYTES=""
SMOKE_TESTS_JSON="[]"
SMOKE_RAW=""

if [[ "$HAVE_PY" == "true" ]]; then
  SMOKE_RAW=$(python3 - <<'PYAI' 2>&1
import json, time
result = {"backend": "skipped", "tests": [], "peak_gflops": None, "peak_memory_used_bytes": None, "error": None}

def run_pytorch():
    import torch
    if not torch.cuda.is_available():
        return None
    torch.cuda.empty_cache()
    device = torch.device("cuda")
    peak_g = 0.0; peak_m = 0
    deadline = time.time() + 55
    tests = []
    size = 4096
    a = torch.randn((size, size), dtype=torch.float16, device=device)
    b = torch.randn((size, size), dtype=torch.float16, device=device)
    torch.cuda.synchronize()
    t0 = time.time(); n = 0
    while time.time() < deadline - 30 and n < 50:
        c = a @ b; torch.cuda.synchronize(); n += 1
    elapsed = time.time() - t0
    if n > 0 and elapsed > 0:
        gflops = (2 * size**3 * n) / elapsed / 1e9
        peak_g = max(peak_g, gflops)
        tests.append({"name": "matmul_fp16_%d" % size, "iterations": n, "duration_sec": round(elapsed, 3), "gflops": round(gflops, 1), "ok": True})
    peak_m = max(peak_m, torch.cuda.memory_allocated())
    del a, b, c; torch.cuda.empty_cache()
    size = 8192
    a = torch.randn((size, size), dtype=torch.float16, device=device)
    b = torch.randn((size, size), dtype=torch.float16, device=device)
    torch.cuda.synchronize()
    t0 = time.time(); n = 0
    while time.time() < deadline:
        c = a @ b; torch.cuda.synchronize(); n += 1
    elapsed = time.time() - t0
    if n > 0 and elapsed > 0:
        gflops = (2 * size**3 * n) / elapsed / 1e9
        peak_g = max(peak_g, gflops)
        tests.append({"name": "matmul_fp16_%d" % size, "iterations": n, "duration_sec": round(elapsed, 3), "gflops": round(gflops, 1), "ok": True})
    peak_m = max(peak_m, torch.cuda.memory_allocated())
    return {"backend": "pytorch_cuda", "tests": tests, "peak_gflops": round(peak_g, 1), "peak_memory_used_bytes": peak_m}

def run_numpy():
    import numpy as np
    size = 2048
    deadline = time.time() + 30
    a = np.random.rand(size, size).astype("float32")
    b = np.random.rand(size, size).astype("float32")
    t0 = time.time(); n = 0
    while time.time() < deadline:
        c = a @ b; n += 1
    elapsed = time.time() - t0
    gflops = 0.0; tests = []
    if n > 0 and elapsed > 0:
        gflops = (2 * size**3 * n) / elapsed / 1e9
        tests.append({"name": "matmul_fp32_%d_cpu" % size, "iterations": n, "duration_sec": round(elapsed, 3), "gflops": round(gflops, 1), "ok": True})
    return {"backend": "numpy_cpu", "tests": tests, "peak_gflops": round(gflops, 1), "peak_memory_used_bytes": None}

out = None
try:
    out = run_pytorch()
except ImportError:
    pass
except Exception as e:
    result["error"] = "pytorch: " + str(e)[:200]

if out is None:
    try:
        out = run_numpy()
    except ImportError:
        result["backend"] = "no_libs"
        if not result["error"]:
            result["error"] = "neither torch nor numpy is available"
    except Exception as e:
        result["backend"] = "numpy_error"
        if not result["error"]:
            result["error"] = "numpy: " + str(e)[:200]

if out:
    result.update(out)

print(json.dumps(result))
PYAI
)
  SMOKE_LAST=$(echo "$SMOKE_RAW" | tail -1)
  if [[ "$HAVE_JQ" == "true" ]] && echo "$SMOKE_LAST" | jq . >/dev/null 2>&1; then
    SMOKE_BACKEND=$(echo "$SMOKE_LAST" | jq -r '.backend // "unknown"')
    SMOKE_PEAK_GFLOPS=$(echo "$SMOKE_LAST" | jq -r '.peak_gflops // empty')
    SMOKE_PEAK_MEM_BYTES=$(echo "$SMOKE_LAST" | jq -r '.peak_memory_used_bytes // empty')
    SMOKE_TESTS_JSON=$(echo "$SMOKE_LAST" | jq -c '.tests // []')
  fi
fi
SMOKE_DURATION=$(( $(date +%s) - SMOKE_START ))

wait "$THERMAL1_PID" 2>/dev/null || true
[[ -r "${TK_REPORT_DIR}/tk_thermal1_$$" ]] && THERMAL_SNAPSHOT_1=$(cat "${TK_REPORT_DIR}/tk_thermal1_$$")
rm -f "${TK_REPORT_DIR}/tk_thermal1_$$" 2>/dev/null

wait "$BENCH_PID" 2>/dev/null || true
BENCH_RESULT=""
if [[ -r "${TK_REPORT_DIR}/tk_bench_result_$$" ]]; then
  BENCH_RESULT=$(cat "${TK_REPORT_DIR}/tk_bench_result_$$")
  rm -f "${TK_REPORT_DIR}/tk_bench_result_$$" 2>/dev/null
fi

JSON_AI=$(printf '{"performed":%s,"backend":%s,"duration_sec":%s,"tests":%s,"peak_gflops":%s,"peak_memory_used_bytes":%s,"raw_log":%s}' \
  "$([[ "$SMOKE_BACKEND" != "skipped" ]] && echo true || echo false)" \
  "$(json_string_or_null "$SMOKE_BACKEND")" \
  "$(json_num_or_null "$SMOKE_DURATION")" \
  "$SMOKE_TESTS_JSON" \
  "$(json_num_or_null "$SMOKE_PEAK_GFLOPS")" \
  "$(json_num_or_null "$SMOKE_PEAK_MEM_BYTES")" \
  "$(json_string_or_null "$SMOKE_RAW")")

# Storage bench (collected from background) -- merged into AI smoke step
if [[ -n "$BENCH_RESULT" ]]; then
  JSON_STORAGE="$BENCH_RESULT"
fi
log_ok

# ============================================================================
# STEP 9: NVMe SMART
# ============================================================================
log_step "Reading NVMe SMART"
SMART_DEVS_JSON="[]"
if [[ "$HAVE_NVME" == "true" ]] && [[ "$HAVE_JQ" == "true" ]]; then
  NVME_LIST=$(sudo_run nvme list -o json 2>/dev/null)
  [[ -z "$NVME_LIST" ]] && NVME_LIST=$(nvme list -o json 2>/dev/null || echo '')
  if [[ -n "$NVME_LIST" ]]; then
    DEVS=""
    while IFS= read -r DEV; do
      [[ -z "$DEV" ]] && continue
      SMART_RAW=$(sudo_run nvme smart-log "$DEV" 2>/dev/null)
      [[ -z "$SMART_RAW" ]] && SMART_RAW=$(nvme smart-log "$DEV" 2>/dev/null || true)
      [[ -z "$SMART_RAW" ]] && continue
      POH=$(echo "$SMART_RAW" | awk -F: '/^power_on_hours/{gsub(/[^0-9]/,"",$2); print $2; exit}')
      PCT_USED=$(echo "$SMART_RAW" | awk -F: '/^percentage_used/{gsub(/[^0-9]/,"",$2); print $2; exit}')
      MEDIA_ERR=$(echo "$SMART_RAW" | awk -F: '/^media_errors/{gsub(/[^0-9]/,"",$2); print $2; exit}')
      TEMP_C=$(echo "$SMART_RAW" | awk -F: '/^temperature/{gsub(/[^0-9]/,"",$2); print $2; exit}')
      CRIT_W=$(echo "$SMART_RAW" | awk -F: '/^critical_warning/{sub(/^ +/,"",$2); print $2; exit}')
      POW_CYC=$(echo "$SMART_RAW" | awk -F: '/^power_cycles/{gsub(/[^0-9]/,"",$2); print $2; exit}')
      DUW=$(echo "$SMART_RAW" | awk -F: '/^data_units_written/{gsub(/[^0-9]/,"",$2); print $2; exit}')
      D=$(printf '{"name":%s,"power_on_hours":%s,"percentage_used_pct":%s,"media_errors":%s,"temperature_c":%s,"critical_warning":%s,"power_cycles":%s,"data_units_written":%s,"raw_smart_log":%s}' \
        "$(json_string "$DEV")" \
        "$(json_num_or_null "$POH")" \
        "$(json_num_or_null "$PCT_USED")" \
        "$(json_num_or_null "$MEDIA_ERR")" \
        "$(json_num_or_null "$TEMP_C")" \
        "$(json_string_or_null "$CRIT_W")" \
        "$(json_num_or_null "$POW_CYC")" \
        "$(json_num_or_null "$DUW")" \
        "$(json_string_or_null "$SMART_RAW")")
      DEVS="${DEVS:+${DEVS},}${D}"
    done < <(echo "$NVME_LIST" | jq -r '.Devices[]?.DevicePath // empty' 2>/dev/null)
    SMART_DEVS_JSON="[${DEVS}]"
  fi
fi
JSON_SMART=$(printf '{"available":%s,"devices":%s}' \
  "$([[ "$HAVE_NVME" == "true" ]] && echo true || echo false)" \
  "$SMART_DEVS_JSON")
log_ok

# ============================================================================
# STEP 10: Network -- Linux ip + Mac ifconfig fallback
# ============================================================================
log_step "Checking network"
IFS_JSON="[]"
FIRST_MAC=""
IFS_LIST=""

if [[ "$HAVE_IP" == "true" ]]; then
  while IFS= read -r IFACE; do
    [[ -z "$IFACE" || "$IFACE" == "lo" ]] && continue
    MAC=$(cat "/sys/class/net/$IFACE/address" 2>/dev/null || echo "")
    [[ -z "$MAC" ]] && continue
    [[ -z "$FIRST_MAC" ]] && FIRST_MAC="$MAC"
    MAC_HASH="sha256:$(printf '%s' "$MAC" | sha256)"
    SPEED=$(cat "/sys/class/net/$IFACE/speed" 2>/dev/null || echo "")
    DUPLEX=$(cat "/sys/class/net/$IFACE/duplex" 2>/dev/null || echo "")
    CARRIER=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo "0")
    TYPE="ethernet"
    [[ "$IFACE" =~ ^wl ]] && TYPE="wireless"
    IPV4=$(ip -4 -o addr show "$IFACE" 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1)
    OBJ=$(printf '{"name":%s,"type":%s,"speed_mbps":%s,"duplex":%s,"carrier":%s,"mac_hash":%s,"ipv4":%s}' \
      "$(json_string "$IFACE")" \
      "$(json_string "$TYPE")" \
      "$(json_num_or_null "$SPEED")" \
      "$(json_string_or_null "$DUPLEX")" \
      "$([[ "$CARRIER" == "1" ]] && echo true || echo false)" \
      "$(json_string "$MAC_HASH")" \
      "$(json_string_or_null "$IPV4")")
    IFS_LIST="${IFS_LIST:+${IFS_LIST},}${OBJ}"
  done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//')
elif [[ "$HAVE_IFCONFIG" == "true" ]]; then
  # Mac/BSD fallback
  IF_LIST_RAW=$(ifconfig -l 2>/dev/null || ifconfig 2>/dev/null | awk '/^[a-z]/{print $1}' | sed 's/://')
  for IFACE in $IF_LIST_RAW; do
    [[ "$IFACE" == "lo0" || "$IFACE" == "lo" ]] && continue
    DETAILS=$(ifconfig "$IFACE" 2>/dev/null || true)
    [[ -z "$DETAILS" ]] && continue
    MAC=$(echo "$DETAILS" | awk '/ether/{print $2; exit}')
    [[ -z "$MAC" ]] && continue
    [[ -z "$FIRST_MAC" ]] && FIRST_MAC="$MAC"
    MAC_HASH="sha256:$(printf '%s' "$MAC" | sha256)"
    IPV4=$(echo "$DETAILS" | awk '/inet /{print $2; exit}')
    STATUS=$(echo "$DETAILS" | awk '/status:/{print $2; exit}')
    CARRIER="false"
    [[ "$STATUS" == "active" ]] && CARRIER="true"
    TYPE="ethernet"
    [[ "$IFACE" =~ ^en ]] && TYPE="ethernet"
    [[ "$IFACE" =~ ^(wl|wlan|wlp) ]] && TYPE="wireless"
    OBJ=$(printf '{"name":%s,"type":%s,"speed_mbps":null,"duplex":null,"carrier":%s,"mac_hash":%s,"ipv4":%s}' \
      "$(json_string "$IFACE")" \
      "$(json_string "$TYPE")" \
      "$CARRIER" \
      "$(json_string "$MAC_HASH")" \
      "$(json_string_or_null "$IPV4")")
    IFS_LIST="${IFS_LIST:+${IFS_LIST},}${OBJ}"
  done
fi
IFS_JSON="[${IFS_LIST}]"

PUBLIC_IP=""
INTERNET_UP="false"
if [[ "$HAVE_CURL" == "true" ]]; then
  PUBLIC_IP=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)
  [[ -n "$PUBLIC_IP" ]] && INTERNET_UP="true"
fi

JSON_NET=$(printf '{"interfaces":%s,"public_ip":%s,"internet_up":%s}' \
  "$IFS_JSON" \
  "$(json_string_or_null "$PUBLIC_IP")" \
  "$INTERNET_UP")
log_ok

# ============================================================================
# STEP 11: Thermal/Power 2 snapshots
# ============================================================================
log_step "Reading thermal/power"
sleep 2
SNAP2=""
if [[ "$HAVE_NVSMI" == "true" ]]; then
  SNAP2=$(nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.gr,clocks.mem,pstate --format=csv,noheader 2>/dev/null | head -1)
fi
CPU_TEMP_C=""
for ZONE in /sys/class/thermal/thermal_zone*/temp; do
  [[ -r "$ZONE" ]] || continue
  T=$(cat "$ZONE" 2>/dev/null)
  [[ -n "$T" ]] && CPU_TEMP_C=$((T / 1000)) && break
done
THROTTLE_RAW=""
if [[ "$HAVE_NVSMI" == "true" ]]; then
  THROTTLE_RAW=$(nvidia-smi -q -d PERFORMANCE 2>/dev/null | awk '/Clocks Throttle Reasons|Clocks Event Reasons/,/^$/' || true)
fi

parse_snap() {
  local s="$1"
  GPU_T=$(echo "$s" | awk -F, '{gsub(/[^0-9]/,"",$1); print $1}')
  GPU_P=$(echo "$s" | awk -F, '{gsub(/[^0-9.]/,"",$2); print $2}')
  GPU_GR=$(echo "$s" | awk -F, '{gsub(/[^0-9]/,"",$3); print $3}')
  GPU_M=$(echo "$s" | awk -F, '{gsub(/[^0-9]/,"",$4); print $4}')
  GPU_PS=$(echo "$s" | awk -F, '{gsub(/^[ ]+/,"",$5); gsub(/[ ]+$/,"",$5); print $5}')
}

SNAP1_JSON="null"
if [[ -n "$THERMAL_SNAPSHOT_1" ]]; then
  parse_snap "$THERMAL_SNAPSHOT_1"
  SNAP1_JSON=$(printf '{"gpu_temp_c":%s,"gpu_power_w":%s,"gpu_clocks_graphics_mhz":%s,"gpu_clocks_memory_mhz":%s,"gpu_pstate":%s}' \
    "$(json_num_or_null "$GPU_T")" "$(json_num_or_null "$GPU_P")" \
    "$(json_num_or_null "$GPU_GR")" "$(json_num_or_null "$GPU_M")" \
    "$(json_string_or_null "$GPU_PS")")
fi
SNAP2_JSON="null"
if [[ -n "$SNAP2" ]]; then
  parse_snap "$SNAP2"
  SNAP2_JSON=$(printf '{"gpu_temp_c":%s,"gpu_power_w":%s,"gpu_clocks_graphics_mhz":%s,"gpu_clocks_memory_mhz":%s,"gpu_pstate":%s}' \
    "$(json_num_or_null "$GPU_T")" "$(json_num_or_null "$GPU_P")" \
    "$(json_num_or_null "$GPU_GR")" "$(json_num_or_null "$GPU_M")" \
    "$(json_string_or_null "$GPU_PS")")
fi
JSON_THERMAL=$(printf '{"under_load":%s,"after_load":%s,"cpu_temp_c":%s,"raw_throttle_reasons":%s,"raw_snap1":%s,"raw_snap2":%s}' \
  "$SNAP1_JSON" "$SNAP2_JSON" \
  "$(json_num_or_null "$CPU_TEMP_C")" \
  "$(json_string_or_null "$THROTTLE_RAW")" \
  "$(json_string_or_null "$THERMAL_SNAPSHOT_1")" \
  "$(json_string_or_null "$SNAP2")")
log_ok

# ============================================================================
# STEP 12: Fingerprint + delivery
# ============================================================================
log_step "Sending report"
FP_INPUT=""
[[ -n "${BOARD_SH:-}" ]] && FP_INPUT="${FP_INPUT}${BOARD_SH}"
[[ -n "${FIRST_MAC:-}" ]] && FP_INPUT="${FP_INPUT}|${FIRST_MAC}"
FP_INPUT="${FP_INPUT}|${CPU_MODEL:-}"
FP_FULL=$(printf '%s' "$FP_INPUT" | sha256)
FP_SHORT="${FP_FULL:0:12}"

JSON_FINGERPRINT=$(printf '{"short":%s,"full":%s}' \
  "$(json_string "$FP_SHORT")" \
  "$(json_string "$FP_FULL")")

TK_FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
TK_DURATION=$(( $(date +%s) - TK_START_EPOCH ))

REPORT=$(printf '{"schema_version":"%s","report_id":"%s","fingerprint":"%s","fingerprint_full":"%s","started_at_utc":"%s","finished_at_utc":"%s","duration_sec":%d,"client":{"version":"tirekicker/%s","platform":"%s","arch":"%s","sudo_used":%s},"errors":[%s],"os":%s,"system":%s,"hwid":%s,"freshness":%s,"gpu":%s,"dmesg":%s,"ai_smoke":%s,"storage_bench":%s,"nvme_smart":%s,"network":%s,"thermal_power":%s}' \
  "$TK_SCHEMA_VERSION" "$TK_RUN_ID" "$FP_SHORT" "$FP_FULL" \
  "$TK_STARTED_AT" "$TK_FINISHED_AT" "$TK_DURATION" \
  "$TK_VERSION" \
  "$(uname -s | tr '[:upper:]' '[:lower:]')" \
  "$ARCH" \
  "$([[ "$SUDO_OK" == "true" ]] && echo true || echo false)" \
  "$ERRORS_JSON" \
  "$JSON_OS" "$JSON_SYSTEM" "$JSON_HWID" "$JSON_FRESHNESS" \
  "$JSON_GPU" "$JSON_DMESG" "$JSON_AI" "${JSON_STORAGE:-null}" \
  "$JSON_SMART" "$JSON_NET" "$JSON_THERMAL")

echo "$REPORT" > "$TK_REPORT_FILE"

if [[ "$TK_DRY_RUN" == "1" ]]; then
  log_skip "dry-run"
  echo
  echo "--- Report saved: $TK_REPORT_FILE ---"
  if [[ "$HAVE_JQ" == "true" ]]; then
    echo "$REPORT" | jq . | head -120
    echo "(truncated; full JSON at $TK_REPORT_FILE)"
  else
    echo "$REPORT" | head -200
  fi
else
  DELIVERED="false"
  SIG=$(printf '%s' "$REPORT" | hmac_sha256_hex "$TK_HMAC_KEY")

  # Tier 1: n8n direct -- DISABLED (n8n not in use in v0; keep block as comment)
  # if [[ -n "$TK_N8N_DIRECT_URL" ]] && [[ "$HAVE_CURL" == "true" ]]; then
  #   if curl -fsSL --max-time 8 -X POST -H 'Content-Type: application/json' \
  #      -H "X-Tirekicker-Signature: $SIG" \
  #      --data-binary @"$TK_REPORT_FILE" "$TK_N8N_DIRECT_URL" >/dev/null 2>&1; then
  #     DELIVERED="true"
  #   fi
  # fi

  # Tier 1: CF Worker (Telegram bot proxy)
  if [[ "$DELIVERED" == "false" ]] && [[ "$HAVE_CURL" == "true" ]]; then
    if curl -fsSL --max-time 8 -X POST -H 'Content-Type: application/json' \
       -H "X-Tirekicker-Signature: $SIG" \
       --data-binary @"$TK_REPORT_FILE" "$TK_WORKER_REPORT_URL" >/dev/null 2>&1; then
      DELIVERED="true"
    fi
  fi
  # Tier 2: file upload
  if [[ "$DELIVERED" == "false" ]] && [[ "$HAVE_CURL" == "true" ]]; then
    UPLOAD_URL=$(curl -fsSL --max-time 10 -F "file=@$TK_REPORT_FILE" https://0x0.st 2>/dev/null | tail -1)
    if [[ -z "$UPLOAD_URL" || ! "$UPLOAD_URL" =~ ^https ]]; then
      UPLOAD_URL=$(curl -fsSL --max-time 10 -F "reqtype=fileupload" -F "fileToUpload=@$TK_REPORT_FILE" https://catbox.moe/user/api.php 2>/dev/null | tail -1)
    fi
    if [[ -z "$UPLOAD_URL" || ! "$UPLOAD_URL" =~ ^https ]]; then
      UPLOAD_URL=$(curl -fsSL --max-time 10 --upload-file "$TK_REPORT_FILE" "https://transfer.sh/tirekicker-${TK_RUN_ID}.json" 2>/dev/null | tail -1)
    fi
    if [[ -n "$UPLOAD_URL" ]] && [[ "$UPLOAD_URL" =~ ^https ]]; then
      curl -fsSL --max-time 5 -X POST -H 'Content-Type: application/json' \
        -d "{\"url\":\"$UPLOAD_URL\",\"fingerprint\":\"$FP_SHORT\",\"report_id\":\"$TK_RUN_ID\"}" \
        "$TK_WORKER_RELAY_URL" >/dev/null 2>&1 || true
      DELIVERED="upload_only"
      printf " %sOK (via file upload: %s)%s\n" "$C_OK" "$UPLOAD_URL" "$C_RESET"
    fi
  fi

  if [[ "$DELIVERED" == "true" ]]; then
    log_ok
  elif [[ "$DELIVERED" != "upload_only" ]]; then
    log_fail "all delivery tiers failed"
    echo
    echo "Local file saved at: $TK_REPORT_FILE"
    echo "Please send this file path to the buyer."
  fi
fi

echo
printf "%sDone.%s\n" "$C_BOLD" "$C_RESET"
echo "Wait at the seller's place until the buyer says 'go ahead, pay' on Telegram."
echo
