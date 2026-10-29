# GitHub Team Management Script

A Bash utility for managing teams, team memberships, and repository permissions in an existing GitHub organization using the [GitHub CLI (`gh`)](https://cli.github.com/).

Inspired by https://github.com/joshjohanning/github-misc-scripts/blob/main/gh-cli/add-user-to-team.sh.

The script supports:
- Adding users to an existing team.
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

Clone or download this repository, then make the script executable:

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

Blank lines and lines beginning with `#` are ignored.

Use GitHub usernames, not display names or email addresses.

## Usage

```text
./manage-github-team.sh [OPTIONS]
```

### Options

| Option | Description |
|---|---|
| `--org ORG` | GitHub organization name. Required. |
| `--team SLUG` | Existing team slug. |
| `--create-team` | Create a new team. |
| `--team-name NAME` | Display name for a new team. Used with `--create-team`. |
| `--privacy closed\|secret` | Privacy setting for a newly created team, if supported by the script. |
| `--repo REPO` | Repository name within the organization. |
| `--permission LEVEL` | Repository permission: `pull`, `triage`, `push`, `maintain`, or `admin`. |
| `--users FILE` | File containing GitHub usernames. |
| `--role member\|maintainer` | Team role assigned to users. Defaults to `member` if not specified. |
| `--dry-run` | Display planned operations without applying changes. |
| `--verbose` | Print API command details for debugging. |
| `--help` | Display usage information, if implemented by the script. |

Use `--team` to target an existing team, or `--create-team --team-name` to create a new one. Do not use both modes in the same invocation.

## Examples

### 1. Add users to an existing team

```bash
./manage-github-team.sh \
  --org magic-telescopes \
  --team magic-members \
  --users users.txt
```

The script attempts to add each listed user to `magic-members` with the default team role.

### 2. Add users as team maintainers

```bash
./manage-github-team.sh \
  --org magic-telescopes \
  --team magic-members \
  --users maintainers.txt \
  --role maintainer
```

Team maintainers can have additional responsibilities for managing the team. This role does not make them organization owners or automatically grant repository administrator permissions.

### 3. Grant a team access to a repository

```bash
./manage-github-team.sh \
  --org magic-telescopes \
  --team magic-members \
  --repo my-repository \
  --permission triage
```

The permission levels are:

| Permission | Typical capabilities |
|---|---|
| `pull` | Read repository contents and participate in discussions. |
| `triage` | Manage issues and pull requests without write access to repository contents. |
| `push` | Read and write repository contents. |
| `maintain` | Manage the repository without having full administrative control. |
| `admin` | Full repository administration, subject to GitHub's permission model. |

Choose the least-privileged level that meets the team's needs.

### 4. Create a team and grant repository access

```bash
./manage-github-team.sh \
  --org magic-telescopes \
  --create-team \
  --team-name "External Contributors" \
  --repo my-repository \
  --permission triage \
  --users users.txt
```

This workflow creates a team, grants it the specified repository permission, and attempts to add the listed users.

The script must have sufficient permissions for each operation. Team creation, repository access changes, and membership changes may have different permission requirements.

### 5. Preview changes

Before applying changes, use dry-run mode:

```bash
./manage-github-team.sh \
  --org magic-telescopes \
  --team magic-members \
  --users users.txt \
  --dry-run
```

For a new team:

```bash
./manage-github-team.sh \
  --org magic-telescopes \
  --create-team \
  --team-name "External Contributors" \
  --repo my-repository \
  --permission triage \
  --users users.txt \
  --dry-run
```

Dry-run mode is intended to preview the planned operations without modifying GitHub. If a new team's slug is estimated before creation, the final slug may differ from the preview.

### 6. Troubleshooting

Add verbose output when investigating a failure:

```bash
./manage-github-team.sh \
  --org magic-telescopes \
  --team magic-members \
  --users users.txt \
  --verbose
```

Verbose mode should print diagnostic information without combining GitHub CLI's mutually exclusive output flags, such as `--verbose` and `--jq`.

## Permissions and common errors

### `HTTP 422: Inviter has insufficient permissions`

This can occur when the authenticated user cannot perform the requested membership operation.

Check:
- Whether the target user is already a member of the organization.
- Whether the user is an outside collaborator rather than an organization member.
- Whether the authenticated account has sufficient team-management permissions.
- Whether organization policies require an owner to invite the user.

Access to an individual repository does not necessarily imply organization membership. An organization owner may need to invite an outside collaborator to the organization before they can be added to a team.

### `HTTP 403: Resource not accessible by integration` or `Resource not accessible by personal access token`

Check the token's scopes or fine-grained permissions, as well as the authenticated account's organization role and repository access.

For classic personal access tokens, team-management operations may require the `admin:org` scope. Fine-grained tokens use different permission settings. A token scope alone does not override the permissions of its owner or organization policies.

### `HTTP 404: Not Found`

Verify:
- The organization name.
- The team slug, which is not always identical to the team's display name.
- The repository name.
- Whether the authenticated account can access the requested resource.

GitHub may return `404` for resources that the caller is not authorized to view.

## Operational notes

- **Existing organizations only:** the script does not create organizations.
- **Least privilege:** grant only the repository permissions required.
- **Partial failures:** a failure for one user may not prevent subsequent users from being processed. Check the final summary and resolve failed operations individually.
- **No privilege escalation:** the script performs API requests as the authenticated user.
- **Review before execution:** use `--dry-run` before bulk changes.
- **API limits:** large lists may encounter GitHub API rate limits or organization policy restrictions.

## References

- [GitHub CLI documentation](https://cli.github.com/manual/)
- [GitHub REST API — Teams](https://docs.github.com/en/rest/teams/teams)
- [GitHub REST API — Team members](https://docs.github.com/en/rest/teams/members)
- [GitHub REST API — Team repositories](https://docs.github.com/en/rest/teams/teams#add-or-update-team-repository-permissions)
- [GitHub documentation — Organization roles](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization)

