#requires -Version 5.1
<#
.SYNOPSIS
  Query GitLab MR reviewers/discussions or reply to one discussion.
.DESCRIPTION
  Compatible with Windows PowerShell 5.1. No jq dependency.
  Reply requires -ConfirmPost and a UTF-8 file containing the message.
.EXAMPLE
  .\gitlab-mr-review.ps1 -Action list -ProjectId 123 -MrIid 45
.EXAMPLE
  .\gitlab-mr-review.ps1 -Action reply -ProjectId 123 -MrIid 45 -DiscussionId abc -BodyFile .\reply.txt -ConfirmPost
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('reviewers','list','reply')]
    [string]$Action,
    [Parameter(Mandatory=$true)]
    [ValidateRange(1,2147483647)]
    [int]$ProjectId,
    [Parameter(Mandatory=$true)]
    [ValidateRange(1,2147483647)]
    [int]$MrIid,
    [string]$DiscussionId,
    [string]$BodyFile,
    [switch]$ConfirmPost
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:GITLAB_URL) -or [string]::IsNullOrWhiteSpace($env:GITLAB_TOKEN)) {
    throw 'GITLAB_URL and GITLAB_TOKEN environment variables are required.'
}
$baseUrl = $env:GITLAB_URL.TrimEnd('/')
if ($baseUrl -notmatch '^https?://[^/]+') { throw 'GITLAB_URL must begin with https:// or http://.' }
$headers = @{ 'PRIVATE-TOKEN' = $env:GITLAB_TOKEN }
$mrPath = "$baseUrl/api/v4/projects/$ProjectId/merge_requests/$MrIid"

function Get-Paged {
    param([Parameter(Mandatory=$true)][string]$Path)
    $page = 1
    $all = New-Object System.Collections.ArrayList
    while ($true) {
        if ($page -gt 10000) { throw 'Pagination safety limit reached.' }
        $separator = if ($Path.Contains('?')) { '&' } else { '?' }
        $uri = "$Path${separator}per_page=100&page=$page"
        $result = @(Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop)
        foreach ($item in $result) { [void]$all.Add($item) }
        if ($result.Count -lt 100) { break }
        $page++
    }
    return ,($all.ToArray())
}

function Get-Discussion {
    param([Parameter(Mandatory=$true)][string]$Id)
    return Invoke-RestMethod -Uri "$mrPath/discussions/$([uri]::EscapeDataString($Id))" -Method Get -Headers $headers -ErrorAction Stop
}

function Test-OpenDiscussion {
    param($Discussion)
    return (@($Discussion.notes | Where-Object { $_.resolvable -eq $true -and $_.resolved -eq $false }).Count -gt 0)
}

function Test-ClosedDiscussion {
    param($Discussion)
    $resolvable = @($Discussion.notes | Where-Object { $_.resolvable -eq $true })
    return ($resolvable.Count -gt 0 -and @($resolvable | Where-Object { $_.resolved -ne $true }).Count -eq 0)
}

try {
    if ($Action -eq 'reviewers') {
        $reviewers = @(Get-Paged "$mrPath/reviewers")
        $reviewers | ForEach-Object {
            [pscustomobject]@{
                reviewer = $_.user.username
                state = $_.state
            }
        } | ConvertTo-Json -Depth 10 -Compress | Write-Output
        if ($reviewers.Count -eq 0) { Write-Output '[]' }
    }
    elseif ($Action -eq 'list') {
        $discussions = @(Get-Paged "$mrPath/discussions")
        $items = @(
            foreach ($d in $discussions) {
                $notes = @($d.notes | Where-Object { $_.system -ne $true })
                if ($notes.Count -eq 0) { continue }
                $kind = if (Test-OpenDiscussion $d) { 'unresolved' }
                        elseif (Test-ClosedDiscussion $d) { 'resolved' }
                        else { 'triage' }
                if ($kind -eq 'resolved') { continue }
                [pscustomobject]@{
                    kind = $kind
                    discussion_id = $d.id
                    notes = @(
                        foreach ($n in $notes) {
                            [pscustomobject]@{
                                id = $n.id
                                author = $n.author.username
                                body = $n.body
                                resolvable = $n.resolvable
                                resolved = $n.resolved
                                file = $(if ($n.position) { $n.position.new_path } else { $null })
                                old_file = $(if ($n.position) { $n.position.old_path } else { $null })
                                line = $(if ($n.position) { $n.position.new_line } else { $null })
                                old_line = $(if ($n.position) { $n.position.old_line } else { $null })
                                created_at = $n.created_at
                            }
                        }
                    )
                }
            }
        )
        # Unary comma avoids pipeline enumeration; convert an actual array even for 0/1 items.
        ConvertTo-Json -InputObject $items -Depth 12 -Compress | Write-Output
    }
    elseif ($Action -eq 'reply') {
        if ([string]::IsNullOrWhiteSpace($DiscussionId)) { throw 'DiscussionId is required for reply.' }
        if ([string]::IsNullOrWhiteSpace($BodyFile) -or -not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) {
            throw 'A readable BodyFile is required for reply.'
        }
        $body = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $BodyFile).ProviderPath, (New-Object System.Text.UTF8Encoding($false)))
        if ([string]::IsNullOrWhiteSpace($body)) { throw 'BodyFile must not be empty.' }
        $discussion = Get-Discussion $DiscussionId
        if (-not (Test-OpenDiscussion $discussion)) {
            throw 'The discussion is not open/resolvable. Refusing reply; inspect it manually.'
        }
        if (@($discussion.notes | Where-Object { $_.body -eq $body }).Count -gt 0) {
            throw 'Identical reply already exists. Refusing duplicate.'
        }
        if (-not $ConfirmPost) {
            [pscustomobject]@{ dry_run = $true; discussion_id = $DiscussionId; body = $body } |
                ConvertTo-Json -Depth 5 -Compress | Write-Output
            exit 0
        }
        $uri = "$mrPath/discussions/$([uri]::EscapeDataString($DiscussionId))/notes"
        $result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body @{ body = $body } -ErrorAction Stop
        [pscustomobject]@{ posted = $true; discussion_id = $DiscussionId; note_id = $result.id } |
            ConvertTo-Json -Compress | Write-Output
    }
}
catch {
    Write-Error "GitLab operation failed: $($_.Exception.Message)"
    exit 1
}
