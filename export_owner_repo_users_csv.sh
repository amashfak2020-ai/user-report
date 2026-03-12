#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./export_owner_repo_users_csv.sh <owner> [token] [output_csv]

Description:
  Combines existing scripts to fetch owner repositories and corresponding users,
  then exports them to CSV.

Arguments:
  owner       GitHub owner/user (required)
  token       Optional GitHub token (or set GITHUB_TOKEN)
  output_csv  Output CSV path (default: owner_repo_users.csv)

Examples:
  ./export_owner_repo_users_csv.sh octocat
  ./export_owner_repo_users_csv.sh my-user github_pat_xxxxx report.csv
  GITHUB_TOKEN=github_pat_xxxxx ./export_owner_repo_users_csv.sh my-user '' ./report.csv

Output columns:
  repository,username
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage
  exit 1
fi

owner="$1"
cli_token="${2:-}"
token="${cli_token:-${GITHUB_TOKEN:-}}"
out_file="${3:-owner_repo_users.csv}"

if [[ -z "$owner" ]]; then
  echo "Error: owner is required" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repos_script="${script_dir}/get_github_owner_repos.sh"
users_script="${script_dir}/get_github_repo_users.sh"

if [[ ! -f "$repos_script" ]]; then
  echo "Error: required script not found: $repos_script" >&2
  exit 1
fi

if [[ ! -f "$users_script" ]]; then
  echo "Error: required script not found: $users_script" >&2
  exit 1
fi

escape_csv_field() {
  local value="$1"
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}

run_repos_script() {
  if [[ -n "$token" ]]; then
    "$repos_script" "$owner" "$token"
  else
    "$repos_script" "$owner"
  fi
}

run_users_script() {
  local repo="$1"
  if [[ -n "$token" ]]; then
    "$users_script" "$repo" "$token"
  else
    "$users_script" "$repo"
  fi
}

mkdir -p "$(dirname "$out_file")"

tmp_rows="$(mktemp)"
trap 'rm -f "$tmp_rows"' EXIT

# Build TSV rows first: repository<TAB>username
while IFS= read -r repo; do
  [[ -z "$repo" ]] && continue

  users_output="$(run_users_script "$repo" 2>/dev/null || true)"
  if [[ -z "$users_output" ]]; then
    # Keep repo in the report even if contributor lookup is empty.
    printf '%s\t\n' "$repo" >> "$tmp_rows"
    continue
  fi

  while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    printf '%s\t%s\n' "$repo" "$user" >> "$tmp_rows"
  done <<< "$users_output"
done < <(run_repos_script)

# Write CSV file.
{
  printf 'repository,username\n'
  while IFS=$'\t' read -r repo user; do
    escape_csv_field "$repo"
    printf ','
    escape_csv_field "$user"
    printf '\n'
  done < "$tmp_rows"
} > "$out_file"

echo "Export complete: $out_file"
