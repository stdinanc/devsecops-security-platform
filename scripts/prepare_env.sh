#!/usr/bin/env bash
set -euo pipefail

DETECT_FILE="${1:-security-reports/detected-project.json}"

if [[ ! -f "$DETECT_FILE" ]]; then
  echo "[ERROR] Detection file not found: $DETECT_FILE"
  exit 1
fi

has_language() {
  local lang="$1"
  jq -e ".languages.${lang} == true" "$DETECT_FILE" >/dev/null 2>&1
}

package_manager() {
  local lang="$1"
  jq -r ".package_managers.${lang} // empty" "$DETECT_FILE"
}

echo "[INFO] Preparing dependency environment..."

# Python
if has_language "python"; then
  echo "[INFO] Python project detected"

  if command -v python3 >/dev/null 2>&1; then
    python3 -m venv .venv
    source .venv/bin/activate

    python -m pip install --upgrade pip setuptools wheel

    if [[ -f "requirements.txt" ]]; then
      echo "[INFO] Installing Python dependencies from requirements.txt"
      pip install --requirement requirements.txt
    elif [[ -f "pyproject.toml" ]]; then
      echo "[INFO] Installing Python project from pyproject.toml"
      pip install .
    elif [[ -f "Pipfile" ]]; then
      echo "[INFO] Installing Python dependencies with pipenv"
      pip install pipenv
      pipenv install --dev || true
    else
      echo "[WARN] No Python dependency manifest found"
    fi

    deactivate
  else
    echo "[WARN] python3 not found. Skipping Python dependency preparation."
  fi
fi

# Java
if has_language "java"; then
  echo "[INFO] Java project detected"

  export MAVEN_OPTS="-Dmaven.repo.local=${GITHUB_WORKSPACE:-$(pwd)}/.m2/repository"

  if [[ -f "pom.xml" ]]; then
    if command -v mvn >/dev/null 2>&1; then
      echo "[INFO] Preparing Maven dependencies"
      mvn -B -ntp -DskipTests dependency:go-offline || true
      mvn -B -ntp -DskipTests test-compile || true
    else
      echo "[WARN] Maven not found. Skipping Maven preparation."
    fi
  elif [[ -f "gradlew" ]]; then
    echo "[INFO] Preparing Gradle wrapper project"
    chmod +x ./gradlew
    ./gradlew dependencies --no-daemon || true
    ./gradlew classes --no-daemon || true
  elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
    if command -v gradle >/dev/null 2>&1; then
      echo "[INFO] Preparing Gradle project"
      gradle dependencies --no-daemon || true
      gradle classes --no-daemon || true
    else
      echo "[WARN] Gradle not found. Skipping Gradle preparation."
    fi
  else
    echo "[WARN] No Java build manifest found"
  fi
fi

# Node.js
if has_language "node"; then
  echo "[INFO] Node.js project detected"

  if [[ -f "pnpm-lock.yaml" ]]; then
    if command -v corepack >/dev/null 2>&1; then
      corepack enable
    fi
    if command -v pnpm >/dev/null 2>&1; then
      pnpm install --frozen-lockfile || true
    else
      echo "[WARN] pnpm not found"
    fi

  elif [[ -f "yarn.lock" ]]; then
    if command -v corepack >/dev/null 2>&1; then
      corepack enable
    fi
    if command -v yarn >/dev/null 2>&1; then
      yarn install --frozen-lockfile || true
    else
      echo "[WARN] yarn not found"
    fi

  elif [[ -f "package-lock.json" ]]; then
    if command -v npm >/dev/null 2>&1; then
      npm ci || true
    else
      echo "[WARN] npm not found"
    fi

  elif [[ -f "package.json" ]]; then
    if command -v npm >/dev/null 2>&1; then
      npm install || true
    else
      echo "[WARN] npm not found"
    fi
  else
    echo "[WARN] No Node.js dependency manifest found"
  fi
fi

# Go
if has_language "go"; then
  echo "[INFO] Go project detected"

  if [[ -f "go.mod" ]]; then
    if command -v go >/dev/null 2>&1; then
      go mod download || true
      go test ./... -run '^$' || true
    else
      echo "[WARN] Go not found. Skipping Go dependency preparation."
    fi
  else
    echo "[WARN] go.mod not found"
  fi
fi

# .NET
if has_language "dotnet"; then
  echo "[INFO] .NET project detected"

  if command -v dotnet >/dev/null 2>&1; then
    if compgen -G "*.sln" > /dev/null; then
      dotnet restore || true
    elif compgen -G "*.csproj" > /dev/null; then
      dotnet restore || true
    else
      echo "[WARN] .NET project file not found"
    fi
  else
    echo "[WARN] dotnet CLI not found. Skipping .NET dependency preparation."
  fi
fi

echo "[INFO] Dependency environment preparation completed."