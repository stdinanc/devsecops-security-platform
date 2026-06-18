#!/usr/bin/env bash
set -euo pipefail

# ─── Argümanlar ───────────────────────────────────────────────────────────────
REPORT_DIR="${1:-security-reports}"
PROFILE_FILE="${2:-}"           # opsiyonel: configs/scan-profiles/<profile>.yml
TRIVY_JSON="${REPORT_DIR}/trivy-results.json"

# ─── Scan profil YAML'ından tek bir anahtar oku ───────────────────────────────
# Kullanım: read_profile_key <yaml_file> <dotted.key>
read_profile_key() {
  local yaml_file="$1"
  local key_path="$2"
  python3 - "$yaml_file" "$key_path" <<'PYEOF' 2>/dev/null || echo ""
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        d = yaml.safe_load(f)
    val = d
    for k in sys.argv[2].split('.'):
        val = val.get(k, None) if isinstance(val, dict) else None
    print(val if val is not None else '')
except Exception:
    print('')
PYEOF
}

# ─── Scan profil YAML'ından gate ayarlarını yükle ────────────────────────────
load_profile() {
  if [[ -z "$PROFILE_FILE" || ! -f "$PROFILE_FILE" ]]; then
    echo "[WARN] Profile file not found or not specified: '${PROFILE_FILE}'. Using defaults." >&2
    return
  fi

  echo "[INFO] Loading scan profile: ${PROFILE_FILE}"

  local vulnerability_gate secret_gate misconfig_gate fail_sev

  vulnerability_gate="$(read_profile_key "$PROFILE_FILE" 'gates.vulnerability_gate')"
  secret_gate="$(read_profile_key "$PROFILE_FILE" 'gates.secret_gate')"
  misconfig_gate="$(read_profile_key "$PROFILE_FILE" 'gates.misconfig_gate')"
  fail_sev="$(read_profile_key "$PROFILE_FILE" 'fail_on_severity')"

  # Profil değerleri env override'lardan daha düşük öncelikli
  if [[ "${vulnerability_gate}" == "True" || "${vulnerability_gate}" == "true" ]]; then
    : "${FAIL_ON_CRITICAL:=true}"
    : "${FAIL_ON_HIGH:=true}"
  else
    FAIL_ON_CRITICAL="${FAIL_ON_CRITICAL:-false}"
    FAIL_ON_HIGH="${FAIL_ON_HIGH:-false}"
  fi

  if [[ "${secret_gate}" == "True" || "${secret_gate}" == "true" ]]; then
    : "${FAIL_ON_SECRET:=true}"
  else
    FAIL_ON_SECRET="${FAIL_ON_SECRET:-false}"
  fi

  if [[ "${misconfig_gate}" == "True" || "${misconfig_gate}" == "true" ]]; then
    : "${FAIL_ON_MISCONFIG_CRITICAL:=true}"
  else
    FAIL_ON_MISCONFIG_CRITICAL="${FAIL_ON_MISCONFIG_CRITICAL:-false}"
  fi

  # strict profili: MEDIUM'u da fail eşiğine ekle
  if [[ "${fail_sev}" == *"MEDIUM"* ]]; then
    FAIL_ON_MEDIUM="${FAIL_ON_MEDIUM:-true}"
  fi
}


# ─── Gate değişkenlerini yükle ────────────────────────────────────────────────
# Önce profili oku (değerleri set eder), sonra env / hard-coded default'lar devreye girer
load_profile

FAIL_ON_CRITICAL="${FAIL_ON_CRITICAL:-true}"
FAIL_ON_HIGH="${FAIL_ON_HIGH:-true}"
FAIL_ON_MEDIUM="${FAIL_ON_MEDIUM:-false}"
FAIL_ON_SECRET="${FAIL_ON_SECRET:-true}"
FAIL_ON_MISCONFIG_CRITICAL="${FAIL_ON_MISCONFIG_CRITICAL:-true}"

FINAL_STATUS="PASS"

# ─── Yardımcı fonksiyonlar ────────────────────────────────────────────────────
log_info()  { echo "[INFO] $*"; }
log_warn()  { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
mark_fail() { FINAL_STATUS="FAIL"; }

count_vulnerabilities() {
  local severity="$1"
  jq "
    [
      .Results[]?
      | .Vulnerabilities[]?
      | select(.Severity == \"${severity}\")
    ] | length
  " "$TRIVY_JSON"
}

count_secrets() {
  jq "
    [
      .Results[]?
      | .Secrets[]?
    ] | length
  " "$TRIVY_JSON"
}

count_misconfigs() {
  local severity="$1"
  jq "
    [
      .Results[]?
      | .Misconfigurations[]?
      | select(.Severity == \"${severity}\")
    ] | length
  " "$TRIVY_JSON"
}

write_github_summary() {
  local critical_vulns="$1"
  local high_vulns="$2"
  local medium_vulns="$3"
  local secrets="$4"
  local critical_misconfigs="$5"

  if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    return 0
  fi

  local status_icon="✅ PASS"
  if [[ "${FINAL_STATUS}" == "FAIL" ]]; then
    status_icon="❌ FAIL"
  fi

  {
    echo "## Security Quality Gate"
    echo ""
    echo "| Check | Count | Gate |"
    echo "|---|---:|---|"
    echo "| Critical vulnerabilities | ${critical_vulns} | \`FAIL_ON_CRITICAL=${FAIL_ON_CRITICAL}\` |"
    echo "| High vulnerabilities | ${high_vulns} | \`FAIL_ON_HIGH=${FAIL_ON_HIGH}\` |"
    echo "| Medium vulnerabilities | ${medium_vulns} | \`FAIL_ON_MEDIUM=${FAIL_ON_MEDIUM}\` |"
    echo "| Secrets detected | ${secrets} | \`FAIL_ON_SECRET=${FAIL_ON_SECRET}\` |"
    echo "| Critical misconfigurations | ${critical_misconfigs} | \`FAIL_ON_MISCONFIG_CRITICAL=${FAIL_ON_MISCONFIG_CRITICAL}\` |"
    echo ""
    echo "**Final Status: ${status_icon}**"
  } >> "$GITHUB_STEP_SUMMARY"
}

# ─── Ana mantık ───────────────────────────────────────────────────────────────
main() {
  log_info "Starting Security Quality Gate evaluation..."
  log_info "Active gates → CRITICAL=${FAIL_ON_CRITICAL} HIGH=${FAIL_ON_HIGH} MEDIUM=${FAIL_ON_MEDIUM} SECRET=${FAIL_ON_SECRET} MISCONFIG_CRITICAL=${FAIL_ON_MISCONFIG_CRITICAL}"

  if [[ ! -f "$TRIVY_JSON" ]]; then
    log_error "Trivy JSON report not found: $TRIVY_JSON"
    exit 1
  fi

  if ! jq empty "$TRIVY_JSON" >/dev/null 2>&1; then
    log_error "Invalid Trivy JSON report: $TRIVY_JSON"
    exit 1
  fi

  local critical_vulns high_vulns medium_vulns secrets critical_misconfigs

  critical_vulns="$(count_vulnerabilities "CRITICAL")"
  high_vulns="$(count_vulnerabilities "HIGH")"
  medium_vulns="$(count_vulnerabilities "MEDIUM")"
  secrets="$(count_secrets)"
  critical_misconfigs="$(count_misconfigs "CRITICAL")"

  if [[ "$FAIL_ON_CRITICAL" == "true" && "$critical_vulns" -gt 0 ]]; then
    log_error "Critical vulnerabilities detected: $critical_vulns"
    mark_fail
  fi

  if [[ "$FAIL_ON_HIGH" == "true" && "$high_vulns" -gt 0 ]]; then
    log_error "High vulnerabilities detected: $high_vulns"
    mark_fail
  fi

  if [[ "$FAIL_ON_MEDIUM" == "true" && "$medium_vulns" -gt 0 ]]; then
    log_error "Medium vulnerabilities detected: $medium_vulns"
    mark_fail
  fi

  if [[ "$FAIL_ON_SECRET" == "true" && "$secrets" -gt 0 ]]; then
    log_error "Secrets detected: $secrets"
    mark_fail
  fi

  if [[ "$FAIL_ON_MISCONFIG_CRITICAL" == "true" && "$critical_misconfigs" -gt 0 ]]; then
    log_error "Critical misconfigurations detected: $critical_misconfigs"
    mark_fail
  fi

  echo ""
  echo "======== Security Quality Gate Summary ========"
  echo "Critical vulnerabilities:      ${critical_vulns}"
  echo "High vulnerabilities:          ${high_vulns}"
  echo "Medium vulnerabilities:        ${medium_vulns}"
  echo "Secrets detected:              ${secrets}"
  echo "Critical misconfigurations:    ${critical_misconfigs}"
  echo "Final status:                  ${FINAL_STATUS}"
  echo "==============================================="
  echo ""

  write_github_summary \
    "$critical_vulns" \
    "$high_vulns" \
    "$medium_vulns" \
    "$secrets" \
    "$critical_misconfigs"

  if [[ "$FINAL_STATUS" == "FAIL" ]]; then
    log_error "Security Quality Gate FAILED."
    exit 1
  fi

  log_info "Security Quality Gate PASSED."
}

main "$@"