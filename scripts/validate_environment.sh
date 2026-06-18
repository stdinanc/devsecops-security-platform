#!/usr/bin/env bash
set -euo pipefail

REQUIRED_TOOLS=(
  git
  curl
  jq
  python3
  trivy
)

echo "[INFO] Validating self-hosted runner environment..."

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] Required tool not found: $tool"
    exit 1
  fi

  echo "[OK] $tool found: $(command -v "$tool")"
done

# python3-yaml kontrolü (scan profil YAML parse için zorunlu)
echo ""
echo "[INFO] Checking Python yaml module..."
if ! python3 -c "import yaml" 2>/dev/null; then
  echo "[WARN] PyYAML not found. Installing..."
  pip3 install --quiet pyyaml || python3 -m pip install --quiet pyyaml || {
    echo "[ERROR] Could not install PyYAML. Run: pip3 install pyyaml"
    exit 1
  }
fi
echo "[OK] PyYAML available"

echo ""
echo "[INFO] Tool versions:"
git --version || true
python3 --version || true
jq --version || true
trivy --version || true
curl --version | head -n 1 || true

echo ""
echo "[INFO] Runner environment validation completed successfully."