#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rules_test_dir="$repo_root/firebase/rules-tests"

npm --prefix "$rules_test_dir" ci
npm --prefix "$rules_test_dir" test
