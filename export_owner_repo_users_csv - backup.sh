#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./export_owner_repo_users_csv.sh <org> [token] [output_csv]

Description:
  Combines existing scripts to fetch organization repositories and corresponding users,
  then exports them to CSV with one unique repository row.

Arguments:
  org         GitHub organization (required)
  token       Optional GitHub token (or set GITHUB_TOKEN)
  output_csv  Output CSV path (default: org_repo_users.csv)

Examples:
  ./export_owner_repo_users_csv.sh amashfak2020
  ./export_owner_repo_users_csv.sh amashfak2020 github_pat_xxxxx report.csv
  GITHUB_TOKEN=github_pat_xxxxx ./export_owner_repo_users_csv.sh amashfak2020 '' ./report.csv

Output columns:
  repository,user_1,user_2,...
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

org="$1"
cli_token="${2:-}"
token="${cli_token:-${GITHUB_TOKEN:-}}"
out_file="${3:-org_repo_users.csv}"

if [[ -z "$org" ]]; then
  echo "Error: org is required" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repos_script="${script_dir}/get_github_org_repos.sh"
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
    "$repos_script" "$org" "$token"
  else
    "$repos_script" "$org"
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

# Write CSV file with a unique repository column and additional user columns.
awk -F $'\t' '
  function esc(v, t) {
    t = v
    gsub(/"/, "\"\"", t)
    return "\"" t "\""
  }

  {
    repo = $1
    user = $2

    if (!(repo in repo_seen)) {
      repo_seen[repo] = 1
      repos[++repo_count] = repo
      user_count[repo] = 0
    }

    if (user != "" && !((repo SUBSEP user) in user_seen)) {
      user_seen[repo SUBSEP user] = 1
      users[repo, ++user_count[repo]] = user
      if (user_count[repo] > max_users) {
        max_users = user_count[repo]
      }
    }
  }

  END {
    printf "repository"
    for (i = 1; i <= max_users; i++) {
      printf ",user_%d", i
    }
    printf "\n"

    for (r = 1; r <= repo_count; r++) {
      repo = repos[r]
      printf "%s", esc(repo)
      for (i = 1; i <= max_users; i++) {
        printf ",%s", esc(users[repo, i])
      }
      printf "\n"
    }
  }
' "$tmp_rows" > "$out_file"

echo "Export complete: $out_file"
