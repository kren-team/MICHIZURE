#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

violations=()

while IFS= read -r file; do
  case "$file" in
    .env.example)
      ;;
    .env|.env.*|*/.env|*/.env.*|\
    *google-services.json|*firebase_options.dart|\
    *service-account*.json|*serviceAccount*.json|\
    *.jks|*.keystore|*key.properties)
      violations+=("$file")
      ;;
  esac
done < <(git ls-files)

if ((${#violations[@]} > 0)); then
  printf 'Forbidden live configuration or secret-like files are tracked:\n' >&2
  printf '  %s\n' "${violations[@]}" >&2
  exit 1
fi

private_key_pattern='BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
service_account_pattern='"type"[[:space:]]*:[[:space:]]*"service_account"'

if git grep -I -n -E \
  "$private_key_pattern|$service_account_pattern" \
  -- . ':!tool/check_no_secrets.sh'; then
  printf 'Private key or service-account content was found in tracked files.\n' >&2
  exit 1
fi

printf 'Secret hygiene check: OK\n'
