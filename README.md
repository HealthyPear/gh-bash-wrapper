# GitHub Team Management Script

A Bash utility for managing organization invitations, team memberships, and repository permissions in an existing GitHub organization using the [GitHub CLI (`gh`)](https://cli.github.com/).

Inspired by [joshjohanning/github-misc-scripts](https://github.com/joshjohanning/github-misc-scripts/blob/main/gh-cli/add-user-to-team.sh).

The script supports:

- Inviting users to an existing GitHub organization.
- Adding individual users to an existing team.
- Processing multiple users from a text file.
- Creating a new team.
- Granting a team access to a repository.
- Selecting the repository permission level.
- Assigning team membership roles.
- Previewing planned operations with dry-run mode.

The script does not create or manage GitHub organizations.

## Requirements

- Bash
- [GitHub CLI (`gh`)](https://cli.github.com/) installed and available in `PATH`
- An authenticated GitHub CLI session
- A GitHub account with sufficient permissions for the requested operations

Check the installation:

```bash
gh --version
```

Authenticate with your own GitHub account:

```bash
gh auth login
```

Check your active account:

```bash
gh auth status
```

**Important:** Each person running the script must authenticate independently. The script uses the permissions of the active GitHub CLI account; it does not elevate privileges or bypass organization policies.

## Installation

Clone or download the repository, then make the script executable:

```bash
chmod +x manage-github-team.sh
```

## User list

Create a text file containing the GitHub usernames to process, one per line.

Example: `users.txt`

```text
# External contributors
alice
bob
charlie
```

Blank lines and lines beginning with `#` are ignored. Whitespace surrounding usernames is removed, and duplicate usernames are processed only once.

Use GitHub usernames, not display names or email addresses.

Alternatively, specify individual users directly using `--user`. This option can be repeated and can be combined with `--users`.

## Usage

```text
./manage-github-team.sh [OPTIONS]
```

### Command-line options

| Option | Description |
|---|---|
| `--org ORG` | GitHub organization name. Required. |
| `--user USER` | GitHub username to process. May be repeated. |
| `--users FILE` | File containing GitHub usernames, one per line. |
| `--invite-to-org` | Invite non-members to the organization. Requires an organization owner account with appropriate permissions. |
| `--team SLUG` | Existing team slug. |
| `--create-team` | Create a new team. |
| `--team-name NAME` | Display name for the new team. Required with `--create-team`. |
| `--privacy closed\|secret` | Privacy setting for a newly created team. Defaults to `closed`. |
| `--repo REPO` | Repository name within the organization. |
| `--permission LEVEL` | Repository permission: `pull`, `triage`, `push`, `maintain`, or `admin`. Defaults to `pull`. |
| `--role member\|maintainer` | Team membership role. Defaults to `member`. |
| `--dry-run` | Preview planned operations without making changes. |
| `--verbose` | Print API commands for debugging. Does not enable HTTP request/response tracing. |
| `--help`, `-h` | Display usage information. |

Use `--team` to target an existing team, or `--create-team --team-name` to create a new one. Do not use both modes in the same invocation.

The `--user` and `--users` options can be combined. Duplicate usernames are removed.

## Examples

### 1. Add users to an existing team

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --users users.txt
```

The script attempts to add each listed user to the specified team with the default team role, `member`.

All users must already be active members of the organization. If a user is not an organization member, the operation may fail.

### 2. Add an individual user to a team

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --user alice
```

No text file is required.

To process multiple individual users:

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --user alice \
  --user bob \
  --user charlie
```

### 3. Invite an individual user to the organization

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --user alice \
  --invite-to-org
```

The script checks whether the user is already an active organization member or has a pending invitation. If neither applies, it attempts to invite the user as a regular organization member.

Organization invitations may require acceptance before membership becomes active. The script does not create organizations.

**Permissions:** Inviting users requires an organization owner account with appropriate token permissions. An organization member or team maintainer cannot necessarily perform this operation.

### 4. Invite a user and add them to a team

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --user alice \
  --invite-to-org
```

The script attempts to:

1. Check the user's organization membership status.
2. Invite the user if they are not already a member.
3. Add the user to the team if they are already an active member.

If an invitation is pending or a new invitation is sent, the script skips team membership for that user. **Rerun the command after the user accepts the invitation** to complete team membership.

This behavior also applies when processing a list of users.

### 5. Invite users from a file and add them to a team

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --users users.txt \
  --invite-to-org
```

This is useful for onboarding several contributors. The script handles each username individually and reports invitation, membership, and failure counts in its summary.

### 6. Add users as team maintainers

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --users maintainers.txt \
  --role maintainer
```

The `maintainer` role grants additional team-management capabilities. It does not make users organization owners or automatically grant repository administrator permissions.

### 7. Grant a team access to a repository

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --repo repository-name \
  --permission triage
```

The available repository permissions are:

| Permission | Typical capabilities |
|---|---|
| `pull` | Read repository contents. |
| `triage` | Manage issues and pull requests without write access to repository contents. |
| `push` | Read and write repository contents. |
| `maintain` | Manage the repository without full administrative control. |
| `admin` | Full repository administration, subject to GitHub's permission model. |

Choose the least-privileged permission level that meets the team's needs.

### 8. Create a team and grant repository access

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --create-team \
  --team-name "External Contributors" \
  --repo repository-name \
  --permission triage \
  --users users.txt
```

This workflow creates a team, grants it the specified repository permission, and attempts to add the listed users.

Users who are not active organization members cannot necessarily be added to the new team. To invite them, include `--invite-to-org`:

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --create-team \
  --team-name "External Contributors" \
  --repo repository-name \
  --permission triage \
  --users users.txt \
  --invite-to-org
```

New invitations remain pending until accepted. Rerun the command after acceptance to complete team membership.

Team creation, repository access changes, and organization invitations have different permission requirements. The authenticated account must be authorized for each operation.

### 9. Preview changes

Before applying changes, use dry-run mode:

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --users users.txt \
  --invite-to-org \
  --dry-run
```

For a new team:

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --create-team \
  --team-name "External Contributors" \
  --repo repository-name \
  --permission triage \
  --users users.txt \
  --invite-to-org \
  --dry-run
```

Dry-run mode previews the planned operations without modifying GitHub. When creating a team, the script estimates the new team slug; the actual slug may differ.

### 10. Debug a failed operation

Use verbose mode to print the API commands being executed:

```bash
./manage-github-team.sh \
  --org ORG_NAME \
  --team team-slug \
  --user alice \
  --verbose
```

Verbose mode prints command arguments but does not enable GitHub CLI's HTTP-level `--verbose` output. This avoids conflicts with output options such as `--jq` and `--silent`.

## Permissions and common errors

### `HTTP 422: Inviter has insufficient permissions`

This error can occur when the authenticated account cannot perform the requested membership operation.

Check:

- Whether the user is already an active organization member.
- Whether the user is an outside collaborator rather than an organization member.
- Whether the authenticated account has sufficient team-management permissions.
- Whether organization policies require an owner to invite the user.

Access to an individual repository does not necessarily imply organization membership. An organization owner may need to invite an outside collaborator to the organization before they can be added to a team.

Use `--invite-to-org` when the workflow should explicitly invite non-members. The option does not bypass GitHub's permission requirements.

### `HTTP 403: Resource not accessible by integration` or `Resource not accessible by personal access token`

Check the token's scopes or fine-grained permissions, as well as the authenticated account's organization role and repository access.

For classic personal access tokens, organization membership and team-management operations may require the `admin:org` scope. Fine-grained tokens use different permission settings. A token scope alone does not override the permissions of its owner or organization policies.

### `HTTP 404: Not Found`

Verify:

- The organization name.
- The team slug, which may differ from the team's display name.
- The repository name.
- Whether the authenticated account can access the requested resource.

GitHub may return `404` for resources that the caller is not authorized to view.

### Invitation is pending

A pending invitation is not the same as active organization membership. The script does not attempt to add a pending invitee to a team.

Ask the invitee to accept the invitation, then rerun the relevant command.

## Operational notes

- **Existing organizations only:** the script does not create organizations.
- **Explicit invitations:** users are invited to the organization only when `--invite-to-org` is specified.
- **Least privilege:** grant only the repository permissions required.
- **Partial failures:** a failure for one user may not prevent subsequent users from being processed. Review the summary and resolve failed operations individually.
- **No privilege escalation:** all API requests use the authenticated GitHub CLI account.
- **Review before execution:** use `--dry-run` before bulk changes.
- **API limits:** large lists may encounter GitHub API rate limits or organization policy restrictions.

## References

- [GitHub CLI documentation](https://cli.github.com/manual/)
- [GitHub REST API — Teams](https://docs.github.com/en/rest/teams/teams)
- [GitHub REST API — Team members](https://docs.github.com/en/rest/teams/members)
- [GitHub REST API — Team repositories](https://docs.github.com/en/rest/teams/teams#add-or-update-team-repository-permissions)
- [GitHub REST API — Organization members](https://docs.github.com/en/rest/orgs/members)
- [GitHub documentation — Organization roles](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization)
