#requires -Version 5.1
<#
.SYNOPSIS
  Query GitLab MR reviewers/discussions or reply to one discussion.
.DESCRIPTION
  Compatible with Windows PowerShell 5.1. No jq dependency.
  The token is read from the NOVA_TOKEN environment variable (Windows user level).
  GET responses are decoded as UTF-8 explicitly: Windows PowerShell 5.1 decodes
  responses without a charset as ISO-8859-1, which garbles Korean review text.
  Reply requires -CommitSha (idempotency key), -LastSeenNoteId (the largest
  non-system note ID read from 'list' for that discussion), a UTF-8 body file
  that mentions the SHA, and -ConfirmPost. Without -ConfirmPost it only prints a dry run.
  Exit codes: 0 success or dry run, 1 API/validation failure or refused reply, 2 configuration error.
.EXAMPLE
  .\gitlab-mr-review.ps1 -Action list -ProjectId 123 -MrIid 45
.EXAMPLE
  .\gitlab-mr-review.ps1 -Action reply -ProjectId 123 -MrIid 45 -DiscussionId abc -CommitSha 3f2c1a9 -LastSeenNoteId 1108 -BodyFile .\reply.txt -ConfirmPost
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
    [string]$CommitSha,
    [long]$LastSeenNoteId = 0,
    [string]$BodyFile,
    [switch]$ConfirmPost
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:GITLAB_URL) -or [string]::IsNullOrWhiteSpace($env:NOVA_TOKEN)) {
    [Console]::Error.WriteLine('GITLAB_URL and NOVA_TOKEN environment variables are required. Do not set the token from the agent; ask the user.')
    exit 2
}
$baseUrl = $env:GITLAB_URL.TrimEnd('/')
if ($baseUrl -notmatch '^https?://[^/]+') {
    [Console]::Error.WriteLine('GITLAB_URL must begin with https:// or http://.')
    exit 2
}
$headers = @{ 'PRIVATE-TOKEN' = $env:NOVA_TOKEN }
$mrPath = "$baseUrl/api/v4/projects/$ProjectId/merge_requests/$MrIid"
$pageSize = 100

function Invoke-GitLabGet {
    param([Parameter(Mandatory=$true)][string]$Uri)
    $response = Invoke-WebRequest -Uri $Uri -Method Get -Headers $headers -UseBasicParsing -ErrorAction Stop
    # Decode the raw bytes as UTF-8 instead of trusting the ISO-8859-1 default of Windows PowerShell 5.1.
    $json = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
    # $null = header missing, '' = header present but empty (last page).
    $nextPage = $null
    foreach ($key in $response.Headers.Keys) {
        if ($key -ieq 'X-Next-Page') { $nextPage = ([string]$response.Headers[$key]).Trim() }
    }
    return [pscustomobject]@{ Json = $json; NextPage = $nextPage }
}

function ConvertFrom-JsonArray {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Json)
    if (-not $Json.TrimStart().StartsWith('[')) { throw 'Expected a JSON array response.' }
    # Assign first: Windows PowerShell 5.1 emits a parsed array as ONE object (so @(ConvertFrom-Json ...)
    # would nest it), while PowerShell 7 enumerates it. Piping the variable enumerates it on both.
    $parsed = ConvertFrom-Json -InputObject $Json
    return @($parsed | Where-Object { $null -ne $_ })
}

function Get-Paged {
    param([Parameter(Mandatory=$true)][string]$Path)
    $page = 1
    $all = New-Object System.Collections.ArrayList
    while ($true) {
        $separator = if ($Path.Contains('?')) { '&' } else { '?' }
        $response = Invoke-GitLabGet "$Path${separator}per_page=$pageSize&page=$page"
        $items = @(ConvertFrom-JsonArray $response.Json)
        foreach ($item in $items) { [void]$all.Add($item) }
        if ($null -eq $response.NextPage) {
            # Header missing (e.g. stripped by a proxy): only a short page can safely be the last one.
            if ($items.Count -ge $pageSize) { throw 'X-Next-Page header missing on a full page; refusing a possibly truncated result.' }
            break
        }
        if ($response.NextPage -eq '') { break }
        $next = 0
        if (-not [int]::TryParse($response.NextPage, [ref]$next) -or $next -le $page -or $next -gt 10000) {
            throw "Invalid X-Next-Page: $($response.NextPage)"
        }
        $page = $next
    }
    return $all.ToArray()
}

function Get-Discussion {
    param([Parameter(Mandatory=$true)][string]$Id)
    $response = Invoke-GitLabGet "$mrPath/discussions/$([uri]::EscapeDataString($Id))"
    $discussion = ConvertFrom-Json -InputObject $response.Json
    return $discussion
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

function Test-MentionsSha {
    param([string]$Text, [string]$Sha)
    return ($null -ne $Text -and $Text.IndexOf($Sha, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

try {
    if ($Action -eq 'reviewers') {
        $reviewers = @(Get-Paged "$mrPath/reviewers")
        $items = @(
            foreach ($r in $reviewers) {
                [pscustomobject]@{
                    reviewer = $r.user.username
                    state = $r.state
                }
            }
        )
        # -InputObject keeps 0/1 items as a JSON array (piping a single item would emit a bare object).
        ConvertTo-Json -InputObject $items -Depth 10 -Compress | Write-Output
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
        # -InputObject keeps 0/1 items as a JSON array (piping a single item would emit a bare object).
        ConvertTo-Json -InputObject $items -Depth 12 -Compress | Write-Output
    }
    elseif ($Action -eq 'reply') {
        if ([string]::IsNullOrWhiteSpace($DiscussionId)) { throw 'DiscussionId is required for reply.' }
        if ($CommitSha -notmatch '^[0-9a-fA-F]{7,40}$') { throw 'CommitSha (7-40 hex characters) is required for reply.' }
        if ($LastSeenNoteId -le 0) { throw 'LastSeenNoteId (largest non-system note ID read from list) is required for reply.' }
        if ([string]::IsNullOrWhiteSpace($BodyFile) -or -not (Test-Path -LiteralPath $BodyFile -PathType Leaf)) {
            throw 'A readable BodyFile is required for reply.'
        }
        $body = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $BodyFile).ProviderPath, (New-Object System.Text.UTF8Encoding($false)))
        if ([string]::IsNullOrWhiteSpace($body)) { throw 'BodyFile must not be empty.' }
        if (-not (Test-MentionsSha $body $CommitSha)) { throw 'BodyFile must mention CommitSha so the reply points to the pushed fix.' }
        $discussion = Get-Discussion $DiscussionId
        if (-not (Test-OpenDiscussion $discussion)) {
            throw 'Discussion is not an open resolvable thread (resolved or triage). Refusing reply; report it to the user instead.'
        }
        # Idempotency key = discussion + commit SHA. Unlike a full-body comparison it is not
        # affected by trailing newlines, CRLF, or how the server normalizes the body.
        if (@($discussion.notes | Where-Object { Test-MentionsSha $_.body $CommitSha }).Count -gt 0) {
            throw 'A note mentioning this commit already exists in the discussion. Refusing duplicate.'
        }
        # New review notes since the agent read the thread must be re-reviewed before replying.
        # System notes are ignored: pushing a fix adds "changed this line in version N" system notes.
        $newNotes = @($discussion.notes | Where-Object { $_.system -ne $true -and [long]$_.id -gt $LastSeenNoteId })
        if ($newNotes.Count -gt 0) {
            throw "Discussion has $($newNotes.Count) new note(s) after note $LastSeenNoteId. Refusing reply; re-review the thread first."
        }
        if (-not $ConfirmPost) {
            [pscustomobject]@{ dry_run = $true; discussion_id = $DiscussionId; commit_sha = $CommitSha; last_seen_note_id = $LastSeenNoteId; body = $body } |
                ConvertTo-Json -Depth 5 -Compress | Write-Output
            exit 0
        }
        $uri = "$mrPath/discussions/$([uri]::EscapeDataString($DiscussionId))/notes"
        # A hashtable body is form-urlencoded with UTF-8 percent-encoding, so Korean text survives on 5.1.
        $result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body @{ body = $body } -ErrorAction Stop
        [pscustomobject]@{ posted = $true; discussion_id = $DiscussionId; note_id = $result.id } |
            ConvertTo-Json -Compress | Write-Output
    }
}
catch {
    # Write-Error would become a terminating error under ErrorActionPreference=Stop and skip 'exit 1'.
    [Console]::Error.WriteLine("GitLab operation failed: $($_.Exception.Message)")
    exit 1
}
