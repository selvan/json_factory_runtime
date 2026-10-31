#!/usr/bin/env bash
# Publishes json_factory_runtime_annotation, then json_factory_runtime_generator.
#
# The generator depends on the hosted annotation package, so the annotation
# is published first (skipped if its version is already on pub.dev). The
# generator's pubspec_overrides.yaml is moved aside while it is tested and
# published, so it resolves against pub.dev like a user's project would. The
# file is restored afterwards, even if a step fails.
#
# Usage: scripts/publish.sh [--dry-run] [--force]
#   --dry-run  validate both packages without publishing
#   --force    publish without the confirmation prompt

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES="$ROOT/packages"
ANNOTATION=json_factory_runtime_annotation
GENERATOR=json_factory_runtime_generator

dry_run=false
publish_args=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true; publish_args+=(--dry-run) ;;
    --force) publish_args+=(--force) ;;
    *) echo "Unknown option: $arg" >&2; exit 64 ;;
  esac
done

version_of() {
  sed -n 's/^version:[[:space:]]*//p' "$PACKAGES/$1/pubspec.yaml"
}

is_on_pub_dev() {
  curl -fsS "https://pub.dev/api/packages/$1" 2>/dev/null |
    grep -q "\"version\":\"$2\""
}

publish() {
  echo "==> dart pub publish ${publish_args[*]:-} ($1)"
  if ! $dry_run; then
    (cd "$PACKAGES/$1" && dart pub publish "${publish_args[@]+"${publish_args[@]}"}")
    return
  fi
  # A dry run exits with 65 for warnings as well as errors, so only fail when
  # pub says the package can't be published.
  local log
  log="$(mktemp)"
  (cd "$PACKAGES/$1" && dart pub publish --dry-run) 2>&1 | tee "$log" || true
  if grep -q "can't be published" "$log"; then
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
}

annotation_version="$(version_of "$ANNOTATION")"
generator_version="$(version_of "$GENERATOR")"

# 1. Annotation.
if is_on_pub_dev "$ANNOTATION" "$annotation_version"; then
  echo "==> $ANNOTATION $annotation_version is already on pub.dev, skipping"
  annotation_live=true
else
  (cd "$PACKAGES/$ANNOTATION" && dart pub get >/dev/null)
  publish "$ANNOTATION"
  annotation_live=false
  if ! $dry_run; then
    echo "==> Waiting for $ANNOTATION $annotation_version to appear on pub.dev"
    for _ in $(seq 1 30); do
      if is_on_pub_dev "$ANNOTATION" "$annotation_version"; then
        annotation_live=true
        break
      fi
      sleep 10
    done
    if ! $annotation_live; then
      echo "$ANNOTATION $annotation_version is not on pub.dev after 5 minutes." >&2
      echo "Run this script again once it is; the annotation step will be skipped." >&2
      exit 1
    fi
  fi
fi

# 2. Generator.
if is_on_pub_dev "$GENERATOR" "$generator_version"; then
  echo "==> $GENERATOR $generator_version is already on pub.dev, nothing to do"
  exit 0
fi

overrides="$PACKAGES/$GENERATOR/pubspec_overrides.yaml"
if $annotation_live && [[ -f "$overrides" ]]; then
  mv "$overrides" "$overrides.bak"
  restore() {
    mv "$overrides.bak" "$overrides"
    (cd "$PACKAGES/$GENERATOR" && dart pub get >/dev/null)
  }
  trap restore EXIT
elif ! $annotation_live; then
  # Dry run with an unpublished annotation: only the local copy can resolve.
  echo "==> $ANNOTATION $annotation_version is not on pub.dev yet;" \
    "validating $GENERATOR against the local copy"
fi

echo "==> Testing $GENERATOR"
(cd "$PACKAGES/$GENERATOR" && dart pub get >/dev/null && dart test)

publish "$GENERATOR"
