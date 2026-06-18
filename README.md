# DevSecOps Security Platform

Merkezi ve yeniden kullanılabilir DevSecOps Security Pipeline.  
Herhangi bir GitHub reposu aşağıdaki küçük workflow dosyasını ekleyerek bu platformu tetikleyebilir.

Pipeline; projenin dilini ve bağımlılıklarını otomatik tespit eder,  
SonarQube (SAST/kod kalitesi) ve Trivy (zafiyet, secret, misconfiguration) taraması yapar,  
sonuçları GitHub Security/SARIF ve SonarQube üzerinden görünür kılar,  
kritik risklerde quality gate ile pipeline'ı durdurur.

---

## Önkoşullar — Self-Hosted Runner

Runner üzerinde şu araçların kurulu olması gerekir:

| Araç | Amaç |
|---|---|
| `git` | Kaynak kod checkout |
| `python3` + `jq` + `curl` | Dil tespiti ve rapor işleme |
| `trivy` | Zafiyet / secret / misconfiguration taraması |
| `java` / `mvn` / `node` / `go` / `dotnet` | Proje diline göre bağımlılık kurulumu |

Runner label'ı: `[self-hosted, linux, x64, devsecops]`

---

## Caller Repo Kurulumu

Taramak istediğin repoda şu dosyayı oluştur:

**`.github/workflows/security.yml`**

```yaml
name: DevSecOps Security Scan

on:
  push:
    branches:
      - main
      - develop

  pull_request:
    branches:
      - main
      - develop

  workflow_dispatch:
    inputs:
      scan_profile:
        description: "Security scan profile (standard | strict | third-party)"
        required: false
        default: "standard"
        type: choice
        options:
          - standard
          - strict
          - third-party

permissions:
  contents: read
  security-events: write
  actions: read
  pull-requests: read

jobs:
  security:
    name: Security Pipeline
    uses: stdinanc/devsecops-security-platform/.github/workflows/security-pipeline.yml@v1
    with:
      scan_profile: ${{ github.event.inputs.scan_profile || 'standard' }}
      sonar_project_key: ${{ github.repository_owner }}_${{ github.event.repository.name }}
      sonar_project_name: ${{ github.repository }}
      fail_on_severity: "CRITICAL,HIGH"
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
```

### Gerekli Repository Secrets

Caller repoda şu secret'ları tanımla:

| Secret | Açıklama |
|---|---|
| `SONAR_TOKEN` | SonarQube kullanıcı token'ı |
| `SONAR_HOST_URL` | SonarQube sunucu adresi (ör. `https://sonar.example.com`) |

---

## Scan Profilleri

| Profil | Kullanım | Fail Seviyesi |
|---|---|---|
| `standard` | Dahili repolar için varsayılan | CRITICAL, HIGH |
| `strict` | Production-kritik servisler | CRITICAL, HIGH, MEDIUM |
| `third-party` | Dışarıdan alınan / güvenilmeyen kodlar | CRITICAL, HIGH |

---

## İlk Sürümü Yayınlama (Platform Repo)

Bu platformun `v1` sürümünü tag'lemek için:

```bash
git tag v1
git push origin v1
```

Yeni bir sürüm çıkarmak için semantic versioning kullan: `v1.1`, `v2` vb.
