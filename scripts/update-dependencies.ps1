function Get-GitHubLatestRelease([string] $Owner, [string] $Repo, [string] $Bearer) {
  $Uri = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
  $Headers = @{
    'Accept'='application/vnd.github+json'
    'Authorization'="Bearer $Bearer"
    'X-GitHub-Api-Version'='2022-11-28'
  }
  Invoke-RestMethod -Headers $Headers -Uri $Uri
}

function New-GitHubPullRequest([string] $Owner, [string] $Repo, [string] $Title, [string] $Head, [string] $Base, [string] $Bearer) {
  $Body = "{""title"":""$Title"",""head"":""$Head"",""base"":""$Base""}"
  $Headers = @{
    'Accept'='application/vnd.github+json'
    'Authorization'="Bearer $Bearer"
    'X-GitHub-Api-Version'='2022-11-28'
  }
  $Uri = "https://api.github.com/repos/$Owner/$Repo/pulls"
  Invoke-RestMethod -Body $Body -Headers $Headers -Method Post -Uri $Uri
}

try {
  $ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

  $RepoRoot = Join-Path -Path $PSScriptRoot -ChildPath ".."
  
  $LibraryName = 'SDL'
  $LibraryRepoOwner = 'libsdl-org'
  $LibraryRepo = 'SDL'

  $PackageName = 'SDL2'
  $PackagingRepoOwner = 'ronaldvanmanen'
  $PackagingRepo = 'SDL2-packaging'

  Write-Host "${ScriptName}: Getting latest release of library $LibraryName...'" -ForegroundColor Yellow
  $LatestLibraryRelease = Get-GitHubLatestRelease -Owner $LibraryRepoOwner -Repo $LibraryRepo -Bearer $Env:GITHUB_TOKEN
  $LatestLibraryVersion = $LatestLibraryRelease.name
  Write-Host "${ScriptName}: Latest release of library $LibraryName is '$LatestLibraryVersion'" -ForegroundColor Yellow

  Write-Host "${ScriptName}: Getting latest release of package $PackageName...'" -ForegroundColor Yellow
  $LatestPackageRelease = Get-GitHubLatestRelease -Owner $PackagingRepoOwner -Repo $PackagingRepo -Bearer $Env:GITHUB_TOKEN
  $LatestPackageVersion = $LatestPackageRelease.name
  Write-Host "${ScriptName}: Latest release of package $PackageName is '$LatestPackageVersion'" -ForegroundColor Yellow

  if ($LatestPackageVersion -eq $LatestLibraryVersion) {
      Write-Host "${ScriptName}: We're up-to-date... nothing to do" -ForegroundColor Yellow
      Break
  }

  $GitBranchName = "release/$LatestLibraryVersion-test"
  Write-Host "${ScriptName}: Checking out branch $GitVersionConfigPath...'" -ForegroundColor Yellow
  & git checkout -b $GitBranchName main
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to checkout branch $GitBranchName."
  }

  $GitVersionConfigPath = "$RepoRoot\GitVersion.yml"

  Write-Host "${ScriptName}: Updating $GitVersionConfigPath...'" -ForegroundColor Yellow
  $GitVersionConfig = Get-Content $GitVersionConfigPath
  $UpdatedGitVersionConfig = $GitVersionConfig -Replace 'next-version: ([^\r\n]+)', "next-version: $LatestLibraryVersion"
  Set-Content $GitVersionConfigPath $UpdatedGitVersionConfig -NoNewline

  Push-Location 'sources\SDL'

  Write-Host "${ScriptName}: Fetching changes in submodule 'sources/SDL'...'" -ForegroundColor Yellow
  & git fetch
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to fetch changes in submodule 'sources/SDL'."
  }

  $LibraryReleaseTag = "release-$LatestLibraryVersion"
  
  Write-Host "${ScriptName}: Checking out tag '$LibraryReleaseTag' in submodule 'sources/SDL'...'" -ForegroundColor Yellow
  & git checkout "$LibraryReleaseTag"
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to checkout tag '$LibraryReleaseTag' in submodule 'sources/SDL'."
  }

  Pop-Location

  Write-Host "${ScriptName}: Staging changes to $GitVersionConfigPath...'" -ForegroundColor Yellow
  & git add .
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed add to $GitVersionConfigPath to commit."
  }

  $GitCommitMessage = "Bump $PackageName from $LatestPackageVersion to $LatestLibraryVersion"
  Write-Host "${ScriptName}: Creating new commit '$GitCommitMessage'...'" -ForegroundColor Yellow
  & git commit -m "$GitCommitMessage"
  if ($LastExitCode -ne 0) {
    throw "${ScriptName}: Failed to create new commit."
  }

  Write-Host "${ScriptName}: Pushing commit(s) on $GitBranchName to 'origin'..." -ForegroundColor Yellow
  # & git push --set-upstream origin $GitBranchName
  # if ($LastExitCode -ne 0) {
  #   throw "${ScriptName}: Failed push commit(s) on $GitBranchName to 'origin'."
  # }

  $PullRequestTitle = "Bump $PackageName from $LatestPackageVersion to $LatestLibraryVersion"
  Write-Host "${ScriptName}: Creating pull request '$PullRequestTitle' on GitHub..." -ForegroundColor Yellow
  # New-GitHubPullRequest -Owner $PackagingRepoOwner -Repo $PackagingRepo -Title $PullRequestTitle -Head $GitBranchName -Base 'main' -Bearer $Env:GITHUB_TOKEN
}
catch {
  Write-Host -Object $_
  Write-Host -Object $_.Exception
  Write-Host -Object $_.ScriptStackTrace
  exit 1
}
