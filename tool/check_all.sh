#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$repo_root/tool/check_flutter.sh"
"$repo_root/tool/check_rules.sh"
"$repo_root/tool/check_no_secrets.sh"
