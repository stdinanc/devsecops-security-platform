#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
from collections import Counter

LANGUAGE_EXTENSIONS = {
    "python": [".py"],
    "java": [".java"],
    "node": [".js", ".jsx", ".ts", ".tsx"],
    "go": [".go"],
    "dotnet": [".cs"],
}

MANIFEST_FILES = {
    "python": [
        "requirements.txt",
        "pyproject.toml",
        "Pipfile",
        "poetry.lock",
    ],
    "java": [
        "pom.xml",
        "build.gradle",
        "build.gradle.kts",
        "gradlew",
    ],
    "node": [
        "package.json",
        "package-lock.json",
        "yarn.lock",
        "pnpm-lock.yaml",
    ],
    "go": [
        "go.mod",
        "go.sum",
    ],
    "dotnet": [
        "*.csproj",
        "*.sln",
        "packages.lock.json",
    ],
}

EXCLUDED_DIRS = {
    ".git",
    ".github",
    "node_modules",
    "target",
    "build",
    "dist",
    ".venv",
    "venv",
    "__pycache__",
    ".mvn",
    ".gradle",
    "vendor",
    "security-platform",
}


def should_skip(path: Path) -> bool:
    return any(part in EXCLUDED_DIRS for part in path.parts)


def find_files(root: Path):
    for path in root.rglob("*"):
        if path.is_file() and not should_skip(path):
            yield path


def detect_by_extensions(files):
    counts = Counter()

    for file in files:
        suffix = file.suffix.lower()

        for language, extensions in LANGUAGE_EXTENSIONS.items():
            if suffix in extensions:
                counts[language] += 1

    return counts


def find_manifests(root: Path):
    result = {language: [] for language in MANIFEST_FILES}

    for language, patterns in MANIFEST_FILES.items():
        for pattern in patterns:
            for path in root.rglob(pattern):
                if path.is_file() and not should_skip(path):
                    result[language].append(str(path.relative_to(root)))

    return result


def detect_python_manager(files):
    names = set(Path(f).name for f in files)

    if "poetry.lock" in names:
        return "poetry"
    if "pyproject.toml" in names:
        return "pip-or-poetry"
    if "Pipfile" in names:
        return "pipenv"
    if "requirements.txt" in names:
        return "pip"

    return None


def detect_java_manager(files):
    names = set(Path(f).name for f in files)

    if "pom.xml" in names:
        return "maven"
    if "gradlew" in names or "build.gradle" in names or "build.gradle.kts" in names:
        return "gradle"

    return None


def detect_node_manager(files):
    names = set(Path(f).name for f in files)

    if "pnpm-lock.yaml" in names:
        return "pnpm"
    if "yarn.lock" in names:
        return "yarn"
    if "package-lock.json" in names:
        return "npm"
    if "package.json" in names:
        return "npm"

    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    root = Path(args.root).resolve()

    files = list(find_files(root))
    extension_counts = detect_by_extensions(files)
    manifests = find_manifests(root)

    languages = {}
    for language in LANGUAGE_EXTENSIONS:
        languages[language] = bool(
            extension_counts.get(language, 0) > 0 or manifests.get(language)
        )

    primary_language = "unknown"

    if extension_counts:
        primary_language = extension_counts.most_common(1)[0][0]
    else:
        for language, detected in languages.items():
            if detected:
                primary_language = language
                break

    output = {
        "primary_language": primary_language,
        "languages": languages,
        "extension_counts": dict(extension_counts),
        "manifests": manifests,
        "package_managers": {
            "python": detect_python_manager(manifests["python"]),
            "java": detect_java_manager(manifests["java"]),
            "node": detect_node_manager(manifests["node"]),
            "go": "go-mod" if manifests["go"] else None,
            "dotnet": "nuget" if manifests["dotnet"] else None,
        },
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()