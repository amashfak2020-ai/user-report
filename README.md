# GitHub Repository Users Scripts

This folder contains seven Bash scripts for GitHub repository/user lookup.

## Files

- `get_github_repo_users.sh`: Get users from a public repository.
- `get_github_private_repo_users.sh`: Get users from a private repository.
- `get_github_org_repos.sh`: Get all repositories for an organization.
- `get_github_owner_repos.sh`: Get all repositories for a GitHub owner/user account.
- `get_github_owner_repos_with_users.sh`: Get all owner repositories and contributor users per repository.
- `get_github_owner_repos_users_to_excel.sh`: Get owner repositories + users and export to Excel-friendly output.
- `export_owner_repo_users_csv.sh`: Combine owner-repo and repo-user scripts, then export `repository,username` CSV.

## Prerequisites

- Bash shell (Git Bash, WSL, or Linux/macOS terminal)
- `curl`
- Optional: `jq` (for better JSON parsing)

## Make Scripts Executable

```bash
chmod +x get_github_repo_users.sh
chmod +x get_github_private_repo_users.sh
chmod +x get_github_org_repos.sh
chmod +x get_github_owner_repos.sh
chmod +x get_github_owner_repos_with_users.sh
chmod +x get_github_owner_repos_users_to_excel.sh
chmod +x export_owner_repo_users_csv.sh
```

## 1) Public Repository Script

### Usage

```bash
./get_github_repo_users.sh <owner/repo> [token]
```

### Examples

```bash
./get_github_repo_users.sh amashfak2020/user-report
./get_github_repo_users.sh amashfak2020/user-report github_pat_xxxxxxxxxxxxxxxxxxxx
```

Notes:
- Token is optional for public repos.
- Providing a token increases API rate limits.

## 2) Private Repository Script

### Usage

```bash
./get_github_private_repo_users.sh <owner/repo> [token]
```

### Examples

```bash
./get_github_private_repo_users.sh amashfak2020/user-report github_pat_xxxxxxxxxxxx
GITHUB_TOKEN=github_pat_xxxxxxxxxxxx ./get_github_private_repo_users.sh amashfak2020/user-report
```

Notes:
- Token is required for private repos.
- Script accepts token from argument 2 or `GITHUB_TOKEN` environment variable.

## 3) Organization Repositories Script

### Usage

```bash
./get_github_org_repos.sh <org> [token]
```

### Examples

```bash
./get_github_org_repos.sh amashfak2020
./get_github_org_repos.sh amashfak2020 github_pat_xxxxxxxxxxxx
GITHUB_TOKEN=github_pat_xxxxxxxxxxxx ./get_github_org_repos.sh amashfak2020
```

Notes:
- Without a token, only public org repositories are returned.
- With a token and proper org/repo access, private repositories can be included.

## 4) Owner Repositories Script

### Usage

```bash
./get_github_owner_repos.sh <owner> [token]
```

### Examples

```bash
./get_github_owner_repos.sh octocat
./get_github_owner_repos.sh my-user ghp_xxxxxxxxxxxx
GITHUB_TOKEN=ghp_xxxxxxxxxxxx ./get_github_owner_repos.sh my-user
```

Notes:
- Without a token, only public repositories are returned.
- Private repositories are included only when the token belongs to the same owner account.

## 5) Owner Repositories With Users Script

### Usage

```bash
./get_github_owner_repos_with_users.sh <owner> [token]
```

### Examples

```bash
./get_github_owner_repos_with_users.sh octocat
./get_github_owner_repos_with_users.sh my-user ghp_xxxxxxxxxxxx
GITHUB_TOKEN=ghp_xxxxxxxxxxxx ./get_github_owner_repos_with_users.sh my-user
```

Output format:

```text
owner/repo<TAB>username
```

Notes:
- This script first fetches owner repositories, then fetches contributors for each repository.
- Repositories with no contributors produce no output lines.
- If the token is invalid, the script falls back to public API access and prints a warning.

## 6) Owner Repositories + Users Export Script

### Usage

```bash
./get_github_owner_repos_users_to_excel.sh <owner> [token] [output_file]
```

### Examples

```bash
./get_github_owner_repos_users_to_excel.sh octocat
./get_github_owner_repos_users_to_excel.sh my-user github_pat_xxxxx report.csv
./get_github_owner_repos_users_to_excel.sh my-user github_pat_xxxxx report.xlsx
GITHUB_TOKEN=github_pat_xxxxx ./get_github_owner_repos_users_to_excel.sh my-user '' owner_users.xlsx
```

Output format:
- CSV columns: `repository,username`
- If output ends with `.xlsx`, script tries to create a native Excel file using `python` + `openpyxl`.
- If `.xlsx` conversion is unavailable, script writes a `.csv` fallback.

## 7) Combined Repositories + Users CSV Script

### Usage

```bash
./export_owner_repo_users_csv.sh <org> [token] [output_csv] [parallelism]
```

### Examples

```bash
./export_owner_repo_users_csv.sh amashfak2020
./export_owner_repo_users_csv.sh amashfak2020 github_pat_xxxxx report.csv
./export_owner_repo_users_csv.sh amashfak2020 github_pat_xxxxx report.csv 12
GITHUB_TOKEN=github_pat_xxxxx ./export_owner_repo_users_csv.sh amashfak2020 '' ./report.csv
GITHUB_PARALLELISM=16 ./export_owner_repo_users_csv.sh amashfak2020
```

Notes:
- This wrapper combines `get_github_org_repos.sh` and `get_github_repo_users.sh`.
- `repository` column is unique (one row per repository).
- Additional contributors are exported as columns: `user_1`, `user_2`, `user_3`, ...
- Fetching contributors supports multithreading via `parallelism` arg or `GITHUB_PARALLELISM` env var.

## How To Generate A GitHub Token

Use a Personal Access Token (PAT).

1. Sign in to GitHub.
2. Open token settings:
   - `https://github.com/settings/tokens`
3. Choose token type:
   - Fine-grained token (recommended)
   - Classic token
4. Click `Generate new token`.
5. Set token name and expiration.
6. Set repository access:
   - Choose only the repositories you need.
7. Set permissions:
   - For private repo read access, grant read permissions for repository contents/metadata.
   - For organization-level private repos, ensure the token is authorized for that organization and has required repository access.
   - For classic token, `repo` scope is typically required.
8. Generate token and copy it immediately (GitHub shows it once).

## Safer Token Usage

Instead of passing the token directly on the command line, use an environment variable:

```bash
export GITHUB_TOKEN='your_token_here'
./get_github_private_repo_users.sh owner/repo "$GITHUB_TOKEN"
```

## Troubleshooting

- `401/403/404` from private repo script:
  - Token is invalid, expired, missing scope, or has no access to that repo.
- Empty output:
  - Repo has no contributors exposed by the API, or access is insufficient.
- `bash: /bin/bash not found` on Windows PowerShell:
  - Run scripts in Git Bash or WSL instead of plain PowerShell.

## 8) Automate Monthly Report With GitHub Actions

A workflow is included at:

`.github/workflows/monthly-github-report.yml`

It runs on the 1st day of every month at `02:00 UTC`, and can also be run manually from the Actions tab.

### Required Repository Settings

1. Repository secret:
   - Name: `GH_PAT`
   - Value: GitHub PAT with access to the target organization repositories.
2. Repository variable:
   - Name: `GITHUB_ORG`
   - Value: organization name (example: `amashfak2020`).
3. Optional repository variable:
   - Name: `GITHUB_PARALLELISM`
   - Value: number of concurrent requests (example: `8` or `12`).

### What The Workflow Does

- Runs `export_owner_repo_users_csv.sh` monthly.
- Writes report to `reports/monthly/report-YYYY-MM.csv`.
- Updates `reports/monthly/latest.csv`.
- Uploads `reports/monthly/` as a workflow artifact.
- Commits and pushes report changes back to the repository.
# Dormant_user_report
