#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./export_github_report.sh <owner> [token] [output_dir] [base_name]

Description:
  Export owner repositories + contributors to files usable in Excel and Notepad.

Outputs:
  - <base_name>.csv  (always)
  - <base_name>.txt  (always)
  - <base_name>.xlsx (optional, if python + openpyxl available)

Arguments:
  owner       GitHub owner/user (required)
  token       Optional PAT (or use GITHUB_TOKEN)
  output_dir  Output directory (default: current directory)
  base_name   Base file name (default: report)

Examples:
  ./export_github_report.sh amashfak2020-ai
  ./export_github_report.sh amashfak2020-ai github_pat_xxxxx . report
  GITHUB_TOKEN=github_pat_xxxxx ./export_github_report.sh amashfak2020-ai '' . report
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 4 ]]; then
  usage
  exit 1
fi

owner="$1"
cli_token="${2:-}"
token="${cli_token:-${GITHUB_TOKEN:-}}"
out_dir="${3:-.}"
base_name="${4:-report}"

mkdir -p "$out_dir"
csv_file="${out_dir%/}/${base_name}.csv"
txt_file="${out_dir%/}/${base_name}.txt"
xlsx_file="${out_dir%/}/${base_name}.xlsx"

per_page=100
public_headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
auth_headers=("${public_headers[@]}")
if [[ -n "$token" ]]; then
  auth_headers+=( -H "Authorization: Bearer ${token}" )
fi

LAST_STATUS=""
LAST_BODY=""
token_warning_shown=0

warn_invalid_token_once() {
  [[ "$token_warning_shown" -eq 1 ]] && return 0
  token_warning_shown=1
  echo "Warning: token rejected (HTTP 401). Falling back to public API." >&2
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
    echo "Error: HTTP ${LAST_STATUS} for $url" >&2
    exit 1
  fi

  if [[ "$LAST_STATUS" == "404" ]]; then
    echo "Error: not found: $url" >&2
    exit 1
  fi

  if [[ "$LAST_STATUS" -lt 200 || "$LAST_STATUS" -ge 300 ]]; then
    echo "Error: unexpected HTTP ${LAST_STATUS} for $url" >&2
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
  local base_url="https://api.github.com/users/${owner}/repos"
  local query="type=owner"
  local auth_login response repos

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
  local rows_file="$1"
  {
    printf 'repository,username\n'
    while IFS=$'\t' read -r repo user; do
      local repo_escaped user_escaped
      repo_escaped="${repo//\"/\"\"}"
      user_escaped="${user//\"/\"\"}"
      printf '"%s","%s"\n' "$repo_escaped" "$user_escaped"
    done < "$rows_file"
  } > "$csv_file"
}

write_txt() {
  local rows_file="$1"
  if [[ ! -s "$rows_file" ]]; then
    printf "No data found for owner '%s'.\n" "$owner" > "$txt_file"
  else
    cat "$rows_file" > "$txt_file"
  fi
}

try_build_xlsx() {
  command -v python >/dev/null 2>&1 || return 1

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
    for row in csv.reader(f):
        ws.append(row)

wb.save(xlsx_file)
PY
}

tmp_rows="$(mktemp)"
trap 'rm -f "$tmp_rows"' EXIT

repos="$(list_owner_repos)"
if [[ -n "$repos" ]]; then
  while IFS= read -r repo; do
    [[ -n "$repo" ]] && list_repo_users "$repo"
  done <<< "$repos" | awk '!seen[$0]++' > "$tmp_rows"
fi

write_csv "$tmp_rows"
write_txt "$tmp_rows"

if try_build_xlsx; then
  echo "XLSX: $xlsx_file"
else
  echo "XLSX: not created (python/openpyxl missing)."
fi

echo "CSV:  $csv_file"
echo "TXT:  $txt_file"
