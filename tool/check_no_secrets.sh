#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

notification_env_example='services/notification_api/.env.example'

validate_notification_env_example() {
  local project_id_count=0
  local service_account_count=0
  local port_count=0
  local line

  [[ -f "$notification_env_example" && ! -L "$notification_env_example" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      'FIREBASE_PROJECT_ID=example-project-id')
        ((project_id_count += 1))
        ;;
      'FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"example-project-id"}')
        ((service_account_count += 1))
        ;;
      'PORT=8080')
        ((port_count += 1))
        ;;
      *)
        return 1
        ;;
    esac
  done < "$notification_env_example"

  [[ "$project_id_count" -eq 1 &&
    "$service_account_count" -eq 1 &&
    "$port_count" -eq 1 ]]
}

if git ls-files --error-unmatch "$notification_env_example" >/dev/null 2>&1 &&
  ! validate_notification_env_example; then
  printf 'Notification API environment example contains non-placeholder values.\n' >&2
  exit 1
fi

violations=()

while IFS= read -r file; do
  case "$file" in
    .env.example|"$notification_env_example")
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
  -- . ':!tool/check_no_secrets.sh' ":!$notification_env_example"; then
  printf 'Private key or service-account content was found in tracked files.\n' >&2
  exit 1
fi

printf 'Secret hygiene check: OK\n'
