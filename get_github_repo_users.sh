#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./get_github_repo_users.sh <owner/repo> [token]

Description:
  Prints GitHub usernames who contributed to a public repository.

Arguments:
  owner/repo   Repository in the form "owner/name" (required)
  token        Optional GitHub personal access token to increase rate limits

Examples:
  ./get_github_repo_users.sh torvalds/linux
  ./get_github_repo_users.sh torvalds/linux ghp_xxxxxxxxxxxxxxxxxxxx

Notes:
  - Uses the GitHub contributors API.
  - Automatically fetches all pages (100 users per page).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

repo="$1"
token="${2:-}"

if [[ "$repo" != */* ]]; then
  echo "Error: repo must be in the format owner/repo" >&2
  exit 1
fi

base_url="https://api.github.com/repos/${repo}/contributors"
page=1
per_page=100

headers=(-H "Accept: application/vnd.github+json")
if [[ -n "$token" ]]; then
  headers+=( -H "Authorization: Bearer ${token}" )
fi

extract_logins() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[].login'
  else
    # Fallback parser when jq is unavailable.
    grep -oE '"login"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/'
  fi
}

while :; do
  url="${base_url}?per_page=${per_page}&page=${page}"

  response="$(curl -fsSL "${headers[@]}" "$url")" || {
    echo "Error: failed to fetch contributors for ${repo}" >&2
    echo "Hint: for heavily-used repos, pass a token to avoid rate limits." >&2
    exit 1
  }

  if [[ "$response" == "[]" ]]; then
    break
  fi

  users="$(printf '%s' "$response" | extract_logins)"
  if [[ -z "$users" ]]; then
    break
  fi

  printf '%s\n' "$users"
  ((page++))
done | awk '!seen[$0]++'
