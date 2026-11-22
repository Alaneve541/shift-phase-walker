param(
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]*$')]
    [string]$RepoName = 'shift-phase-walker'
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'Install the official GitHub CLI first, then run gh auth login.'
}
Push-Location $PSScriptRoot
try {
    gh auth status
    if ($LASTEXITCODE -ne 0) { throw 'Run gh auth login, then retry this script.' }
    $owner = gh api user --jq .login
    if ($LASTEXITCODE -ne 0 -or -not $owner) { throw 'Unable to identify the authenticated GitHub account.' }
    git rev-parse --verify HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'This folder needs a local Git commit before publication.' }
    $changes = git status --porcelain
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read repository status.' }
    if ($changes) { throw 'Review and commit the working-tree changes before publishing.' }
    $remotes = git remote
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository remotes.' }
    if ($remotes -contains 'origin') {
        throw 'Origin already exists. Verify it with git remote -v before pushing manually.'
    }
    Write-Host "Creating PUBLIC repository $owner/$RepoName and pushing the current commit."
    gh repo create "$owner/$RepoName" --public --source . --remote origin --push --description 'SHIFT: a two-world HTML5 platformer with three-second echo puzzles. Game Off 2026.'
    if ($LASTEXITCODE -ne 0) {
        throw 'Publication did not fully complete. Inspect gh repo view and git remote -v before retrying.'
    }
    gh repo view "$owner/$RepoName" --json url --jq .url
    if ($LASTEXITCODE -ne 0) { throw 'Creation succeeded, but fetching the repository URL failed.' }
} finally { Pop-Location }
