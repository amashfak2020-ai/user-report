#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./get_github_owner_repos_users_to_excel.sh <owner> [token] [output_file]

Description:
  Fetch all repositories for a GitHub owner and contributor users per repository,
  then export results to an Excel-friendly file.

Arguments:
  owner        GitHub username/owner (required)
  token        Optional GitHub personal access token (or use GITHUB_TOKEN)
  output_file  Optional output file path (default: owner_repos_users.csv)

Examples:
  ./get_github_owner_repos_users_to_excel.sh octocat
  ./get_github_owner_repos_users_to_excel.sh my-user github_pat_xxxxx output.csv
  GITHUB_TOKEN=github_pat_xxxxx ./get_github_owner_repos_users_to_excel.sh my-user '' report.csv

Output:
  - Always writes CSV (Excel can open it directly)
  - If Python + openpyxl are installed and output is .xlsx, writes native Excel .xlsx

Notes:
  - Without token, only public owner repositories are returned.
  - Private repositories are included only when token belongs to the same owner.
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
out_file="${3:-owner_repos_users.csv}"

if [[ -z "$owner" ]]; then
  echo "Error: owner is required" >&2
  exit 1
fi

per_page=100

public_headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
auth_headers=("${public_headers[@]}")
if [[ -n "$token" ]]; then
  auth_headers+=( -H "Authorization: Bearer ${token}" )
fi

token_warning_shown=0
LAST_STATUS=""
LAST_BODY=""

warn_invalid_token_once() {
  [[ "$token_warning_shown" -eq 1 ]] && return 0
  token_warning_shown=1

  echo "Warning: provided token was rejected (HTTP 401). Falling back to public API access." >&2
  if [[ "$token" == ghp_github_pat_* ]]; then
    echo "Hint: token format looks wrong. Use token as copied (often starts with 'github_pat_')." >&2
  fi
}

request_api() {
  local url="$1"
  local mode="$2"
  local raw

  if [[ "$mode" == "auth" ]]; then
    raw="$(curl -sS -L "${auth_headers[@]}" -w $'\n%{http_code}' "$url")"
  else
    raw="$(curl -sS -L "${public_headers[@]}" -w $'\n%{http_code}' "$url")"
  fi

  LAST_STATUS="${raw##*$'\n'}"
  LAST_BODY="${raw%$'\n'*}"
}

api_get() {
  local url="$1"
  local allow_public_fallback="${2:-true}"

  if [[ -n "$token" ]]; then
    request_api "$url" "auth"

    if [[ "$LAST_STATUS" == "401" && "$allow_public_fallback" == "true" ]]; then
      warn_invalid_token_once
      request_api "$url" "public"
    fi
  else
    request_api "$url" "public"
  fi

  if [[ "$LAST_STATUS" == "401" || "$LAST_STATUS" == "403" ]]; then
    if [[ "$allow_public_fallback" == "false" ]]; then
      return 1
    fi
    echo "Error: GitHub API returned HTTP ${LAST_STATUS}. Check token and permissions." >&2
    exit 1
  fi

  if [[ "$LAST_STATUS" == "404" ]]; then
    echo "Error: resource not found: $url" >&2
    exit 1
  fi

  if [[ "$LAST_STATUS" -lt 200 || "$LAST_STATUS" -ge 300 ]]; then
    echo "Error: unexpected HTTP status ${LAST_STATUS} for $url" >&2
    exit 1
  fi

  printf '%s' "$LAST_BODY"
}

json_to_repos() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | select(.full_name != null) | .full_name'
  else
    grep -oE '"full_name"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

json_to_users() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | select(.login != null) | .login'
  else
    grep -oE '"login"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

get_auth_login() {
  [[ -z "$token" ]] && return 1

  local body
  body="$(api_get "https://api.github.com/user" false)" || return 1

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$body" | jq -r '.login // empty'
  else
    printf '%s' "$body" | grep -oE '"login"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

list_owner_repos() {
  local page=1
  local base_url query auth_login response repos

  base_url="https://api.github.com/users/${owner}/repos"
  query="type=owner"

  if [[ -n "$token" ]]; then
    auth_login="$(get_auth_login || true)"
    if [[ -n "$auth_login" && "$auth_login" == "$owner" ]]; then
      base_url="https://api.github.com/user/repos"
      query="affiliation=owner&visibility=all"
    fi
  fi

  while :; do
    response="$(api_get "${base_url}?${query}&per_page=${per_page}&page=${page}")"
    [[ "$response" == "[]" ]] && break

    repos="$(printf '%s' "$response" | json_to_repos)"
    [[ -z "$repos" ]] && break

    printf '%s\n' "$repos"
    ((page++))
  done | awk '!seen[$0]++'
}

list_repo_users() {
  local repo="$1"
  local page=1
  local response users

  while :; do
    response="$(api_get "https://api.github.com/repos/${repo}/contributors?per_page=${per_page}&page=${page}")"
    [[ "$response" == "[]" ]] && break

    users="$(printf '%s' "$response" | json_to_users)"
    [[ -z "$users" ]] && break

    while IFS= read -r user; do
      [[ -n "$user" ]] && printf '%s\t%s\n' "$repo" "$user"
    done <<< "$users"

    ((page++))
  done
}

write_csv() {
  local file="$1"
  local rows_file="$2"

  {
    printf 'repository,username\n'
    while IFS=$'\t' read -r repo user; do
      local repo_escaped user_escaped
      repo_escaped="${repo//\"/\"\"}"
      user_escaped="${user//\"/\"\"}"
      printf '"%s","%s"\n' "$repo_escaped" "$user_escaped"
    done < "$rows_file"
  } > "$file"
}

build_xlsx_from_csv() {
  local csv_file="$1"
  local xlsx_file="$2"

  if command -v python >/dev/null 2>&1; then
    python - "$csv_file" "$xlsx_file" <<'PY'
import csv
import sys

csv_file = sys.argv[1]
xlsx_file = sys.argv[2]

try:
    from openpyxl import Workbook
except Exception:
    sys.exit(2)

wb = Workbook()
ws = wb.active
ws.title = "repos_users"

with open(csv_file, newline='', encoding='utf-8') as f:
    reader = csv.reader(f)
    for row in reader:
        ws.append(row)

wb.save(xlsx_file)
PY
    return $?
  fi

  return 2
}

tmp_rows="$(mktemp)"
trap 'rm -f "$tmp_rows"' EXIT

repos="$(list_owner_repos)"
if [[ -z "$repos" ]]; then
  echo "No repositories found for owner '${owner}'." >&2
  printf '' > "$tmp_rows"
else
  while IFS= read -r repo; do
    [[ -n "$repo" ]] && list_repo_users "$repo"
  done <<< "$repos" | awk '!seen[$0]++' > "$tmp_rows"
fi

# If caller asked for .xlsx, create temporary CSV then convert when possible.
if [[ "$out_file" == *.xlsx ]]; then
  tmp_csv="$(mktemp)"
  trap 'rm -f "$tmp_rows" "$tmp_csv"' EXIT
  write_csv "$tmp_csv" "$tmp_rows"

  if build_xlsx_from_csv "$tmp_csv" "$out_file"; then
    echo "Export complete: $out_file"
  else
    fallback_csv="${out_file%.xlsx}.csv"
    cp "$tmp_csv" "$fallback_csv"
    echo "Warning: could not create .xlsx (python/openpyxl missing)." >&2
    echo "CSV exported instead: $fallback_csv" >&2
  fi
else
  write_csv "$out_file" "$tmp_rows"
  echo "Export complete: $out_file"
fi
