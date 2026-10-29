#!/usr/bin/env bash
# Black-box tests for manage-github-team.sh. No network or real GitHub account needed.
set -uo pipefail

SCRIPT_UNDER_TEST="${SCRIPT_UNDER_TEST:-$(cd "$(dirname "$0")/.." && pwd)/manage-github-team.sh}"
[[ -f "$SCRIPT_UNDER_TEST" ]] || { printf 'Cannot find script: %s\n' "$SCRIPT_UNDER_TEST" >&2; exit 2; }

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
export GH_MOCK_LOG="$TEST_ROOT/gh.log"
export GH_MOCK_MEMBERSHIP_STATE="${GH_MOCK_MEMBERSHIP_STATE:-not_member}"
export GH_MOCK_INVITE_STATE="${GH_MOCK_INVITE_STATE:-pending}"
export GH_MOCK_FAIL_INVITE="${GH_MOCK_FAIL_INVITE:-false}"
export GH_MOCK_FAIL_TEAM_ADD="${GH_MOCK_FAIL_TEAM_ADD:-false}"

cat > "$TEST_ROOT/bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >> "$GH_MOCK_LOG"

if [[ "${1-}" == "auth" && "${2-}" == "status" ]]; then
    exit 0
fi
[[ "${1-}" == "api" ]] && shift

method="GET"
jq=""
endpoint=""
while (($#)); do
    case "$1" in
        --method|-X) method="${2-}"; shift 2 ;;
        --jq|-q) jq="${2-}"; shift 2 ;;
        -f|--raw-field|-F|--header|-H) shift 2 ;;
        --*) shift ;;
        *)
            if [[ -z "$endpoint" ]]; then endpoint="$1"; fi
            shift ;;
    esac
done

case "$endpoint" in
    orgs/*/teams/*/memberships/*)
        if [[ "$method" == "PUT" ]]; then
            [[ "${GH_MOCK_FAIL_TEAM_ADD:-false}" == "true" ]] && exit 1
            if [[ "$jq" == ".state" ]]; then printf 'active\n'; else printf '{"state":"active"}\n'; fi
        else
            exit 1
        fi
        ;;
    orgs/*/memberships/*)
        if [[ "$method" == "PUT" ]]; then
            [[ "${GH_MOCK_FAIL_INVITE:-false}" == "true" ]] && exit 1
            if [[ "$jq" == ".state" ]]; then printf '%s\n' "$GH_MOCK_INVITE_STATE"; else printf '{"state":"%s"}\n' "$GH_MOCK_INVITE_STATE"; fi
        else
            case "$GH_MOCK_MEMBERSHIP_STATE" in
                active|pending) if [[ "$jq" == ".state" ]]; then printf '%s\n' "$GH_MOCK_MEMBERSHIP_STATE"; else printf '{"state":"%s","role":"member"}\n' "$GH_MOCK_MEMBERSHIP_STATE"; fi ;;
                *) exit 1 ;;
            esac
        fi
        ;;
    orgs/*/teams/*)
        if [[ "$jq" == ".slug" ]]; then printf 'test-team\n'; else printf '{"slug":"test-team"}\n'; fi
        ;;
    repos/*/*)
        if [[ "$jq" == ".full_name" ]]; then printf 'test-org/test-repo\n'; else printf '{"full_name":"test-org/test-repo"}\n'; fi
        ;;
    orgs/*/teams)
        if [[ "$jq" == ".slug" ]]; then printf 'test-team\n'; else printf '{"slug":"test-team"}\n'; fi
        ;;
    *)
        printf 'Unexpected mocked gh API request: %s %s\n' "$method" "$endpoint" >&2
        exit 1
        ;;
esac
MOCK_GH
chmod +x "$TEST_ROOT/bin/gh"
export PATH="$TEST_ROOT/bin:$PATH"

pass=0
fail=0

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'ok - %s\n' "$label"
        pass=$((pass + 1))
    else
        printf 'not ok - %s (missing: %s)\n' "$label" "$needle" >&2
        fail=$((fail + 1))
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'ok - %s\n' "$label"
        pass=$((pass + 1))
    else
        printf 'not ok - %s (unexpected: %s)\n' "$label" "$needle" >&2
        fail=$((fail + 1))
    fi
}

run_case() {
    : > "$GH_MOCK_LOG"
    local output status
    output="$("$SCRIPT_UNDER_TEST" "$@" 2>&1)"
    status=$?
    printf '%s' "$output"
    return "$status"
}

# 1. Help exits successfully.
if output="$(run_case --help)"; then
    assert_contains "$output" "Usage:" "--help prints usage"
else
    printf 'not ok - --help exits successfully\n' >&2; fail=$((fail + 1))
fi

# 2. Missing organization is rejected before any API request.
if output="$(run_case --team test-team --user alice 2>&1)"; then
    printf 'not ok - missing --org is rejected\n' >&2; fail=$((fail + 1))
else
    status=$?
    [[ $status -eq 2 ]] && assert_contains "$output" "--org is required" "missing --org is rejected" || { printf 'not ok - missing --org returns status 2\n' >&2; fail=$((fail + 1)); }
fi

# 3. Pending invitation is not sent again and team membership is skipped.
GH_MOCK_MEMBERSHIP_STATE=pending; export GH_MOCK_MEMBERSHIP_STATE
if output="$(run_case --org test-org --team test-team --user alice --invite-to-org)"; then
    assert_contains "$output" "invitation already pending" "pending invitation is recognized"
    assert_not_contains "$(cat "$GH_MOCK_LOG")" "--method PUT orgs/test-org/memberships/alice" "pending invitation is not duplicated"
    assert_not_contains "$(cat "$GH_MOCK_LOG")" "teams/test-team/memberships/alice" "pending user is not added to team"
else
    printf 'not ok - pending invitation scenario exits successfully\n' >&2; fail=$((fail + 1))
fi

# 4. Active member is not reinvited and can be added to a team.
GH_MOCK_MEMBERSHIP_STATE=active; export GH_MOCK_MEMBERSHIP_STATE
if output="$(run_case --org test-org --team test-team --user alice --invite-to-org)"; then
    assert_contains "$output" "already active" "active organization membership is recognized"
    assert_contains "$(cat "$GH_MOCK_LOG")" "--method PUT orgs/test-org/teams/test-team/memberships/alice" "active member is added to team"
    assert_not_contains "$(cat "$GH_MOCK_LOG")" "--method PUT orgs/test-org/memberships/alice" "active member is not reinvited"
else
    printf 'not ok - active member scenario exits successfully\n' >&2; fail=$((fail + 1))
fi

# 5. A non-member is invited; pending result skips team membership.
GH_MOCK_MEMBERSHIP_STATE=not_member; GH_MOCK_INVITE_STATE=pending
export GH_MOCK_MEMBERSHIP_STATE GH_MOCK_INVITE_STATE
if output="$(run_case --org test-org --team test-team --user alice --invite-to-org)"; then
    assert_contains "$output" "Invitation sent to alice" "non-member receives an invitation"
    assert_contains "$(cat "$GH_MOCK_LOG")" "--method PUT orgs/test-org/memberships/alice" "organization invitation API is called"
    assert_not_contains "$(cat "$GH_MOCK_LOG")" "--method PUT orgs/test-org/teams/test-team/memberships/alice" "pending invitee is not added to team"
else
    printf 'not ok - new invitation scenario exits successfully\n' >&2; fail=$((fail + 1))
fi

# 6. Duplicate individual usernames are processed once.
GH_MOCK_MEMBERSHIP_STATE=active; export GH_MOCK_MEMBERSHIP_STATE
if output="$(run_case --org test-org --team test-team --user alice --user alice)"; then
    calls="$(grep -c 'teams/test-team/memberships/alice' "$GH_MOCK_LOG" || true)"
    [[ "$calls" == "1" ]] && assert_contains "$output" "1 team membership operation(s) successful" "duplicate usernames are deduplicated" || { printf 'not ok - duplicate username is processed once (calls=%s)\n' "$calls" >&2; fail=$((fail + 1)); }
else
    printf 'not ok - duplicate user scenario exits successfully\n' >&2; fail=$((fail + 1))
fi

# 7. Dry-run makes no mutating API calls.
if output="$(run_case --org test-org --team test-team --user alice --invite-to-org --dry-run)"; then
    assert_contains "$output" "DRY RUN" "dry-run announces planned operations"
    assert_not_contains "$(cat "$GH_MOCK_LOG")" "--method PUT" "dry-run makes no PUT requests"
else
    printf 'not ok - dry-run scenario exits successfully\n' >&2; fail=$((fail + 1))
fi

# 8. Invalid team role is rejected.
if output="$(run_case --org test-org --team test-team --user alice --role owner)"; then
    printf 'not ok - invalid role is rejected\n' >&2; fail=$((fail + 1))
else
    status=$?
    [[ $status -eq 2 ]] && assert_contains "$output" "--role must be member or maintainer" "invalid role is rejected" || { printf 'not ok - invalid role returns status 2\n' >&2; fail=$((fail + 1)); }
fi

printf '\nTest summary: %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
