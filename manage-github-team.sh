
#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  manage-github-team.sh --org ORG [TEAM OPTIONS] [ACTIONS]

Team options:
  --team SLUG          Use an existing team by slug
  --create-team        Create a new team
  --team-name NAME     Display name for a new team (requires --create-team)
  --privacy LEVEL      Team visibility: closed or secret (default: closed)

Actions:
  --repo REPO          Grant the team access to this repository
  --permission LEVEL   pull, triage, push, maintain, or admin
                       (default: triage; requires --repo)
  --users FILE         Add usernames from a text file to the team
  --role ROLE          Team membership role: member or maintainer
                       (default: member)

General options:
  --dry-run            Preview changes without modifying GitHub
  --verbose            Show verbose GitHub CLI request details
  -h, --help           Show this help

Input files contain one username per line. Blank lines and comments
starting with # are ignored.

Examples:
  # Create a team, grant repository access, and add users
  manage-github-team.sh --org my-org \
    --create-team --team-name "External Contributors" \
    --repo my-repo --permission triage --users users.txt

  # Configure an existing team
  manage-github-team.sh --org my-org --team external-contributors \
    --repo my-repo --permission write --users users.txt
EOF
}

org=""
team=""
team_name=""
repo=""
users_file=""
permission="triage"
role="member"
privacy="closed"
create_team=false
dry_run=false
verbose=false

while (($#)); do
    case "$1" in
        --org|--team|--team-name|--repo|--users|--permission|--role|--privacy)
            if (($# < 2)); then
                echo "Missing value for $1" >&2
                exit 2
            fi

            option=$1
            value=$2
            shift 2

            case "$option" in
                --org)        org=$value ;;
                --team)       team=$value ;;
                --team-name)  team_name=$value ;;
                --repo)       repo=$value ;;
                --users)      users_file=$value ;;
                --permission) permission=$value ;;
                --role)       role=$value ;;
                --privacy)    privacy=$value ;;
            esac
            ;;
        --create-team)
            create_team=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        --verbose)
            verbose=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Validate configuration.
if [[ -z "$org" ]]; then
    echo "--org is required" >&2
    exit 2
fi

if $create_team; then
    if [[ -z "$team_name" || -n "$team" ]]; then
        echo "--create-team requires --team-name and excludes --team" >&2
        exit 2
    fi
else
    if [[ -z "$team" || -n "$team_name" ]]; then
        echo "Specify --team SLUG or --create-team --team-name NAME" >&2
        exit 2
    fi
fi

if [[ -z "$repo" && -z "$users_file" && "$create_team" == false ]]; then
    echo "Specify at least one action: --repo, --users, or --create-team" >&2
    exit 2
fi

if [[ -n "$repo" && "$repo" == */* ]]; then
    echo "--repo expects a repository name, not ORG/REPO" >&2
    exit 2
fi

if [[ -n "$users_file" && ( ! -f "$users_file" || ! -r "$users_file" ) ]]; then
    echo "Input file is missing or unreadable: $users_file" >&2
    exit 1
fi

case "$permission" in
    pull|triage|push|maintain|admin) ;;
    *)
        echo "Invalid repository permission: $permission" >&2
        exit 2
        ;;
esac

case "$role" in
    member|maintainer) ;;
    *)
        echo "Invalid team role: $role" >&2
        exit 2
        ;;
esac

case "$privacy" in
    closed|secret) ;;
    *)
        echo "Invalid team privacy: $privacy" >&2
        exit 2
        ;;
esac

command -v gh >/dev/null || {
    echo "GitHub CLI (gh) is required." >&2
    exit 1
}

gh auth status || exit 1

# Keep the API subcommand before its options.
gh_api() {
    if [[ "$verbose" == true ]]; then
        printf '+ gh api' >&2
        printf ' %q' "$@" >&2
        printf '\n' >&2
    fi

    gh api "$@"
}

# Used only to estimate the slug in dry-run mode.
slugify() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//'
}

errors=0
success=0
skipped=0

# Verify the repository before making changes.
if [[ -n "$repo" ]]; then
    if ! gh_api "repos/$org/$repo" --jq '.full_name' >/dev/null; then
        echo "Cannot access repository: $org/$repo" >&2
        exit 1
    fi
fi

# Resolve an existing team or create one.
if $create_team; then
    if $dry_run; then
        team=$(slugify "$team_name")
        printf '[DRY RUN] Create team "%s" in %s\n' "$team_name" "$org"
        printf '[DRY RUN] Expected team slug: %s\n' "$team"
        ((skipped += 1))
    else
        printf 'Creating team "%s" in %s ...\n' "$team_name" "$org"

        if team=$(gh_api \
            --method POST \
            "orgs/$org/teams" \
            -f "name=$team_name" \
            -f "privacy=$privacy" \
            --jq '.slug'); then
            printf 'Created team: %s\n' "$team"
            ((success += 1))
        else
            echo "Could not create team. Check organization policy and permissions." >&2
            exit 1
        fi
    fi
else
    if ! team=$(gh_api "orgs/$org/teams/$team" --jq '.slug'); then
        echo "Cannot access team: $org/$team" >&2
        exit 1
    fi
fi

# Grant the team repository access.
if [[ -n "$repo" ]]; then
    if $dry_run; then
        printf '[DRY RUN] Grant %s/%s access to %s/%s\n' \
            "$org" "$team" "$org" "$repo"
        printf '[DRY RUN] Repository permission: %s\n' "$permission"
        ((skipped += 1))
    else
        printf 'Granting %s access to %s/%s ...\n' \
            "$team" "$org" "$repo"

        if gh_api \
            --method PUT \
            "orgs/$org/teams/$team/repos/$org/$repo" \
            -f "permission=$permission"; then
            echo "Repository access configured."
            ((success += 1))
        else
            echo "FAILED to configure repository access." >&2
            ((errors += 1))
        fi
    fi
fi

# Add users to the team.
if [[ -n "$users_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}

        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        user=${line//[[:space:]]/}

        if [[ ! "$user" =~ ^[a-zA-Z0-9-]+$ ]]; then
            echo "Invalid username: $line" >&2
            ((errors += 1))
            continue
        fi

        if $dry_run; then
            printf '[DRY RUN] Add %s to %s/%s as %s\n' \
                "$user" "$org" "$team" "$role"
            ((skipped += 1))
            continue
        fi

        printf 'Adding %s to %s/%s ...\n' "$user" "$org" "$team"

        if gh_api \
            --method PUT \
            "orgs/$org/teams/$team/memberships/$user" \
            -f "role=$role" >/dev/null; then
            echo "OK: $user"
            ((success += 1))
        else
            echo "FAILED: $user" >&2
            ((errors += 1))
        fi
    done < "$users_file"
fi

printf '\nSummary: %d successful operations, %d failed, %d dry-run operations\n' \
    "$success" "$errors" "$skipped"

((errors == 0))
