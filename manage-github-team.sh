#!/usr/bin/env bash

# Manage organization invitations, team membership, and team repository access.
# Requires Bash and GitHub CLI (gh). Uses the currently authenticated gh account.

set -uo pipefail

usage() {
    cat <<'USAGE'
Usage:
  manage-github-team.sh --org ORG [OPTIONS]

People:
  --user USER             GitHub username; may be repeated
  --users FILE            File of GitHub usernames, one per line
  --invite-to-org         Invite non-members to the organization (owner permissions required)
  --role ROLE             Team role: member (default) or maintainer

Team:
  --team SLUG             Use an existing team
  --create-team           Create a new team
  --team-name NAME        Display name for the new team (requires --create-team)
  --privacy PRIVACY       New team privacy: closed (default) or secret

Repository:
  --repo REPO             Repository name within ORG
  --permission LEVEL      pull, triage, push, maintain, or admin (default: pull)

General:
  --dry-run               Preview actions without making changes
  --verbose               Print API commands for debugging (does not enable HTTP tracing)
  --help                  Show this help

Examples:
  # Add one existing organization member to a team
  ./manage-github-team.sh --org magic-telescopes --team magic-members --user alice

  # Invite one person to the organization
  ./manage-github-team.sh --org magic-telescopes --user alice --invite-to-org

  # Invite a person, then add them to the team if already an active member
  ./manage-github-team.sh --org magic-telescopes --team magic-members \
    --user alice --invite-to-org

  # Add users from a file and invite non-members first
  ./manage-github-team.sh --org magic-telescopes --team magic-members \
    --users users.txt --invite-to-org

  # Create a team, grant repository access, and process a user list
  ./manage-github-team.sh --org magic-telescopes --create-team \
    --team-name "External Contributors" --repo public-docs \
    --permission triage --users users.txt --dry-run

Notes:
  - Organization invitations are pending until accepted. This script does not
    add a pending invitee to a team; rerun it after they accept.
  - --invite-to-org requires an organization owner and appropriate token permissions.
  - Organization membership, team membership, and repository access are separate.
USAGE
}

org=""
team=""
create_team=false
team_name=""
privacy="closed"
repo=""
permission="pull"
users_file=""
invite_to_org=false
team_role="member"
dry_run=false
verbose=false
users=()

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# Print commands in verbose mode without passing gh's --verbose flag, which is
# mutually exclusive with --jq/--silent/--template.
gh_api() {
    if [[ "$verbose" == true ]]; then
        printf '+ gh api' >&2
        printf ' %q' "$@" >&2
        printf '\n' >&2
    fi
    gh api "$@"
}

add_user() {
    local username="$1"
    [[ -z "$username" ]] && return 0
    # Avoid duplicates without Bash 4 associative arrays (macOS ships Bash 3.2).
    case " ${users[*]-} " in
        *" ${username} "*) ;;
        *) users+=("$username") ;;
    esac
}

while (($#)); do
    case "$1" in
        --org)
            (($# >= 2)) || { err "--org requires a value"; exit 2; }
            org="$2"; shift 2 ;;
        --team)
            (($# >= 2)) || { err "--team requires a value"; exit 2; }
            team="$2"; shift 2 ;;
        --create-team)
            create_team=true; shift ;;
        --team-name)
            (($# >= 2)) || { err "--team-name requires a value"; exit 2; }
            team_name="$2"; shift 2 ;;
        --privacy)
            (($# >= 2)) || { err "--privacy requires a value"; exit 2; }
            privacy="$2"; shift 2 ;;
        --repo)
            (($# >= 2)) || { err "--repo requires a value"; exit 2; }
            repo="$2"; shift 2 ;;
        --permission)
            (($# >= 2)) || { err "--permission requires a value"; exit 2; }
            permission="$2"; shift 2 ;;
        --users)
            (($# >= 2)) || { err "--users requires a file path"; exit 2; }
            users_file="$2"; shift 2 ;;
        --user)
            (($# >= 2)) || { err "--user requires a username"; exit 2; }
            add_user "$2"; shift 2 ;;
        --invite-to-org)
            invite_to_org=true; shift ;;
        --role)
            (($# >= 2)) || { err "--role requires a value"; exit 2; }
            team_role="$2"; shift 2 ;;
        --dry-run)
            dry_run=true; shift ;;
        --verbose)
            verbose=true; shift ;;
        --help|-h)
            usage; exit 0 ;;
        *)
            err "Unknown option: $1"
            usage >&2
            exit 2 ;;
    esac
done

[[ -n "$org" ]] || { err "--org is required"; usage >&2; exit 2; }

if [[ "$create_team" == true ]]; then
    [[ -z "$team" ]] || { err "Use either --team or --create-team, not both"; exit 2; }
    [[ -n "$team_name" ]] || { err "--create-team requires --team-name"; exit 2; }
else
    [[ -z "$team_name" ]] || { err "--team-name requires --create-team"; exit 2; }
fi

case "$privacy" in closed|secret) ;; *) err "--privacy must be closed or secret"; exit 2 ;; esac
case "$team_role" in member|maintainer) ;; *) err "--role must be member or maintainer"; exit 2 ;; esac
case "$permission" in pull|triage|push|maintain|admin) ;; *) err "Invalid --permission: $permission"; exit 2 ;; esac

if [[ -n "$users_file" ]]; then
    [[ -r "$users_file" ]] || { err "Cannot read users file: $users_file"; exit 2; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        # Ignore comments, then trim surrounding whitespace.
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] && add_user "$line"
    done < "$users_file"
fi

# A user list is required when inviting or managing team membership. Creating a
# team or granting its repository access can be done without a user list.
if [[ ( "$invite_to_org" == true || -n "$users_file" || ${#users[@]} -gt 0 ) && ${#users[@]} -eq 0 ]]; then
    err "No usernames supplied; use --user USER and/or --users FILE"
    exit 2
fi
if [[ "$invite_to_org" == false && -z "$team" && "$create_team" == false ]]; then
    err "Specify --invite-to-org, --team, or --create-team"
    exit 2
fi
if [[ ${#users[@]} -gt 0 && "$invite_to_org" == false && -z "$team" && "$create_team" == false ]]; then
    err "Usernames require --invite-to-org or a team"
    exit 2
fi
if [[ -n "$repo" && "$create_team" == false && -z "$team" ]]; then
    err "--repo requires --team or --create-team"
    exit 2
fi

command -v gh >/dev/null 2>&1 || { err "GitHub CLI 'gh' is not installed or not in PATH"; exit 2; }
if ! gh auth status >/dev/null 2>&1; then
    err "GitHub CLI is not authenticated. Run: gh auth login"
    exit 2
fi

failures=0
invites_sent=0
already_members=0
pending_invites=0
team_added=0

# Prepare or validate team before processing people.
if [[ "$create_team" == true ]]; then
    if [[ "$dry_run" == true ]]; then
        team="$(printf '%s' "$team_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//')"
        log "DRY RUN: would create team '$team_name' (estimated slug: $team, privacy: $privacy)"
    else
        log "Creating team '$team_name' in $org ..."
        if team="$(gh_api --method POST "orgs/$org/teams" -f "name=$team_name" -f "privacy=$privacy" --jq '.slug')"; then
            log "Created team: $org/$team"
        else
            err "Failed to create team '$team_name'"
            exit 1
        fi
    fi
elif [[ -n "$team" ]]; then
    if [[ "$dry_run" == true ]]; then
        log "DRY RUN: would use team $org/$team"
    else
        if ! gh_api "orgs/$org/teams/$team" --jq '.slug' >/dev/null; then
            err "Cannot access team: $org/$team"
            exit 1
        fi
    fi
fi

# Apply team repository access once, before processing users.
if [[ -n "$repo" ]]; then
    if [[ "$dry_run" == true ]]; then
        log "DRY RUN: would grant $org/$team access to $org/$repo with permission '$permission'"
    else
        if ! gh_api "repos/$org/$repo" --jq '.full_name' >/dev/null; then
            err "Cannot access repository: $org/$repo"
            exit 1
        fi
        log "Granting $org/$team access to $org/$repo ($permission) ..."
        if gh_api --method PUT "orgs/$org/teams/$team/repos/$org/$repo" -f "permission=$permission" >/dev/null; then
            log "Repository access configured"
        else
            err "Failed to grant repository access to $org/$team"
            failures=$((failures + 1))
        fi
    fi
fi

for username in "${users[@]}"; do
    state=""
    if [[ "$dry_run" == true ]]; then
        if [[ "$invite_to_org" == true ]]; then
            log "DRY RUN: would ensure '$username' is an organization member of '$org'"
        fi
        if [[ -n "$team" ]]; then
            log "DRY RUN: would add '$username' to team '$org/$team' with role '$team_role' (if they are an active organization member)"
        fi
        continue
    fi

    # If requested, invite users who are not already active members. Checking
    # membership first avoids accidentally changing an existing owner's role.
    if [[ "$invite_to_org" == true ]]; then
        state="$(gh_api "orgs/$org/memberships/$username" --jq '.state' 2>/dev/null || true)"
        case "$state" in
            active)
                log "Organization member already active: $username"
                already_members=$((already_members + 1)) ;;
            pending)
                log "Organization invitation already pending: $username"
                pending_invites=$((pending_invites + 1))
                # Do not try team membership until the invite is accepted.
                continue ;;
            *)
                log "Inviting $username to organization $org ..."
                if state="$(gh_api --method PUT "orgs/$org/memberships/$username" -f role=member --jq '.state')"; then
                    if [[ "$state" == "active" ]]; then
                        log "Organization membership active: $username"
                        already_members=$((already_members + 1))
                    else
                        log "Invitation sent to $username; membership state: ${state:-unknown}. They must accept before team access can be assigned."
                        invites_sent=$((invites_sent + 1))
                        pending_invites=$((pending_invites + 1))
                        continue
                    fi
                else
                    err "Failed to invite $username to organization $org"
                    failures=$((failures + 1))
                    continue
                fi ;;
        esac
    fi

    if [[ -n "$team" ]]; then
        log "Adding $username to $org/$team ..."
        if gh_api --method PUT "orgs/$org/teams/$team/memberships/$username" -f "role=$team_role" --jq '.state' >/dev/null; then
            log "Added/updated team membership: $username"
            team_added=$((team_added + 1))
        else
            err "Failed to add $username to team $org/$team"
            if [[ "$invite_to_org" == false ]]; then
                warn "If the user is not an active organization member, rerun with --invite-to-org using an organization owner's account."
            fi
            failures=$((failures + 1))
        fi
    fi
done

if [[ "$dry_run" == true ]]; then
    log "Summary: dry-run complete; no changes made."
else
    log ""
    log "Summary: $invites_sent invitation(s) sent, $already_members already-active member(s), $pending_invites pending invitation(s), $team_added team membership operation(s) successful, $failures failure(s)."
fi

(( failures == 0 ))
