[CmdletBinding()]
param (
    [string]$Server,
    [Alias("FullName")]
    [string[]]$FilePath,
    [string]$Type,
    [switch]$Recurse
)
<#

            Validation

#>
if (-not $FilePath) {
    Write-Warning "FilePath empty or missing"
    return
}
Write-Verbose "Starting process with the following files:"
$FilePath | Write-Output

. $PSScriptRoot/helpers.ps1
$myaccount = Invoke-Request -Path "accounts/verify_credentials" -Method GET
$myid = $myaccount.id
$followcount = $myaccount.following_count

$script:accounts = New-Object System.Collections.ArrayList

$linkpaths = $FilePath | Where-Object { $PSItem.StartsWIth("http") }
$localpath = $FilePath | Where-Object { $PSItem -notin $linkpaths }

if ($localpath) {
    $alllocal = (Get-ChildItem -Path $localpath -File -Recurse:$Recurse -Filter *.csv -ErrorAction Stop).FullName
    $zips = $localpath | Where-Object { "$PSItem".EndsWith("zip") }
    $localzipfiles = @()
    foreach ($zip in $zips) {
        $filename = Split-Path -Path $zip -Leaf
        $basename = (Get-ChildItem -Path $zip).BaseName
        $dir = Join-Path -Path $([System.IO.Path]::GetTempPath()) -ChildPath $basename
        $null = New-Item -Path $dir -Type Directory -ErrorAction Ignore
        $null = Expand-Archive -Path $zip -DestinationPath $dir -Force
        $localzipfiles += (Get-ChildItem -Path $dir -File -Recurse:$Recurse -Filter *.csv -ErrorAction Stop).FullName
    }
}

if ($linkpaths) {
    $zips = $linkpaths | Where-Object { "$PSItem".EndsWith("zip") }
    $remotezipfiles = @()
    foreach ($zip in $zips) {
        Write-Verbose "Downloading zip from $zip"
        $filename = Split-Path -Path $zip -Leaf
        $fullname = Join-Path -Path $([System.IO.Path]::GetTempPath()) -ChildPath $filename
        $null = Invoke-WebRequest -Uri $zip -OutFile $fullname
        $fullname = Get-ChildItem -Path $fullname
        $dir = Join-Path -Path $([System.IO.Path]::GetTempPath()) -ChildPath $fullname.BaseName
        $null = New-Item -Path $dir -Type Directory -ErrorAction Ignore
        $null = Expand-Archive -Path $fullname.FullName -DestinationPath $dir -Force
        $remotezipfiles += (Get-ChildItem -Path $dir -File -Recurse:$Recurse -Filter *.csv -ErrorAction Stop).FullName
    }
}

$allfiles = @()
if ($linkpaths) {
    $allfiles += $linkpaths
}
if ($alllocal) {
    $allfiles += $alllocal
}
if ($remotezipfiles) {
    $allfiles += $remotezipfiles
}
if ($localzipfiles) {
    $allfiles += $localzipfiles
}

$allfiles = $allfiles | Where-Object { $PSItem -notmatch ".zip" } | Select-Object -Unique

# help 'em out
if ($Server -match '://') {
    $Server = ([uri]$Server).DnsSafeHost
} elseif ($Server -match '/@') {
    $Server = $($Server -split "/@" | Select-Object -First 1)
} elseif ($Server.StartsWith("@") -or $Server -match "@") {
    $Server = $($Server -split "@" | Select-Object -Last 1)
}


Write-Output "Pre-processing complete. We will now import the following files:"
$allfiles | Write-Output

foreach ($file in $allfiles) {
    Write-Verbose "Processing $file"

    if ($file -match "://") {
        Write-Verbose "Downloading file from $file"
        $filename = Split-Path -Path $file -Leaf
        $fullname = Join-Path -Path $([System.IO.Path]::GetTempPath()) -ChildPath $filename
        $null = Invoke-WebRequest -Uri $file -OutFile $fullname
        $file = $fullname
    }

    if (-not (Test-Path -Path $file -PathType Leaf)) {
        Write-Verbose "$file does not exist or is unsupported"
        continue
    }

    $first = Get-Content $file -First 1
    Write-Verbose "first line of $file"
    Write-Verbose "$first"

    if (-not $PSBoundParameter.Type) {
        if ($first -match "Hide Notifications") {
            $Type = "mutes"
            $csv = Import-Csv -Path $file
        } elseif ($first -match "Show boosts") {
            $Type = "follows"
            $csv = Import-Csv -Path $file
        } elseif ($first -match "@" -and $first -notmatch ",") {
            $Type = "accountblocks"
            $csv = Get-Content -Path $file
        } elseif ($first -match "@" -and $first -match ",") {
            $Type = "lists"
            $csv = Import-Csv -Path $file -Header List, UserName
        } elseif ($first -notmatch "," -and $first -match "http") {
            $Type = "bookmarks"
            $csv = Get-Content -Path $file
        } elseif ($first -notmatch "http" -and $first -notmatch "," -and $first -match ".") {
            $Type = "domainblocks"
            $csv = Get-Content -Path $file
        } else {
            $basename = Split-Path -Path $file -Leaf
            throw "Can't auto-detect file type for $basename. Please specify type in the Action"
        }
    }


    Write-Verbose "File is type $Type"

    if ($Type -eq "follows") {
        if (-not $script:blocked) {
            Write-Verbose "Getting current blocks for follow comparison"
            $script:blocked = Invoke-Request -Path "blocks" -Method GET -UseWebRequest

            while ($null -ne $script:link) {
                $script:blocked += Invoke-Request -Path $script:link -Method GET -UseWebRequest
            }

            foreach ($blockacct in $script:blocked.acct) {
                $blockacct = "@" + $blockacct
            }
        }

        if ($followcount -lt 3000 -and $csv.count -gt 25) {
            Write-Verbose "Getting current follows for comparison"
            $followed = Invoke-Request -Path "accounts/$myid/followers?limit=80" -Method GET -UseWebRequest

            while ($null -ne $script:link) {
                $followed += Invoke-Request -Path $script:link -Method GET -UseWebRequest
            }

            foreach ($follow in $followed) {
                $follow.acct = "@" + $follow.acct
            }
            $alreadyfollowed = $csv | Where-Object 'Account address' -in $followed.acct
            $notfollowed = $csv | Where-Object 'Account address' -notin $followed.acct

            Write-Verbose "Following $followcount accounts. $($csv.count) in the csv file. $($alreadyfollowed.count) already followed. Trying to follow $($notfollowed.count) new accounts"
            $csv = $notfollowed | Where-Object 'Account address' -notin $blocked.acct
        }

        foreach ($item in $csv) {
            try {
                $address = $item.'Account address'
                $account = Get-Account -UserName $address
            } catch {
                Write-Warning "$address not found"
                continue
            }
            if ($account.id.Count -eq 1) {
                $id = $account.id
                try {
                    $parms = @{
                        Path = "accounts/$id/follow"
                    }
                    $body = @{}
                    if ($item.'Show Boosts') {
                        $body["reblog"] = $item.'Show Boosts'
                    }
                    if ($item.Languages) {
                        $body["languages"] = $item.Languages
                    }
                    if ($item.'Notify on new posts') {
                        $body["notify"] = $item.'Notify on new posts'
                    }

                    if ($body.count -gt 0) {
                        $parms.Body = $body | ConvertTo-Json
                    }
                    $null = Invoke-Request @parms
                    [pscustomobject]@{
                        Address = $account.acct
                        Type    = $Type
                        Status  = "Success"
                    }
                } catch {
                    [pscustomobject]@{
                        Address = $account.acct
                        Type    = $Type
                        Status  = $PSItem
                    }
                }
            }
        }
    }

    if ($Type -eq "mutes") {
        $muted = Invoke-Request -Path "mutes" -Method GET
        foreach ($mute in $muted) {
            $mute.acct = "@" + $mute.acct
        }
        $alreadymuted = $csv | Where-Object 'Account address' -in $muted.acct
        $notmuted = $csv | Where-Object 'Account address' -notin $muted.acct

        Write-Verbose "Muted $($muted.count) accounts. $($csv.count) in the csv file. $($alreadymuted.count) already followed. Trying to mute $($notmuted.count) new accounts"

        foreach ($address in $notmuted) {
            try {
                $account = Get-Account -UserName $address.acct
            } catch {
                Write-Warning "$address not found"
                continue
            }
            if ($account.id.Count -eq 1) {
                $id = $account.id
                try {
                    $null = Invoke-Request -Path "accounts/$id/mute"
                    [pscustomobject]@{
                        Address = $account.acct
                        Type    = $Type
                        Status  = "Success"
                    }
                } catch {
                    [pscustomobject]@{
                        Address = $account.acct
                        Type    = $Type
                        Status  = $PSItem
                    }
                }
            }
        }
    }


    if ($Type -eq "accountblocks") {
        if (-not $script:blocked) {
            $script:blocked = Invoke-Request -Path "blocks" -Method GET -UseWebRequest

            while ($null -ne $script:link) {
                $script:blocked += Invoke-Request -Path $script:link -Method GET -UseWebRequest
            }

            foreach ($blockacct in $script:blocked.acct) {
                $blockacct = "@" + $blockacct
            }
        }

        $alreadyblocked = $csv | Where-Object { $PSItem -in $script:blocked.acct }
        $notblocked = $csv | Where-Object { $PSItem -notin $script:blocked.acct }

        Write-Verbose "Blocked $($script:blocked.count) accounts. $($csv.count) in the csv file. $($alreadyblocked.count) already blocked. Trying to block $($notblocked.count) new accounts"

        foreach ($address in $notblocked) {
            try {
                $account = Get-Account -UserName $address
            } catch {
                Write-Warning "$address not found"
                continue
            }
            if ($account.id.Count -eq 1) {
                $id = $account.id
                try {
                    $null = Invoke-Request -Path "accounts/$id/block"
                    [pscustomobject]@{
                        Address = $account.acct
                        Type    = $Type
                        Status  = "Success"
                    }
                } catch {
                    [pscustomobject]@{
                        Address = $account.acct
                        Type    = $Type
                        Status  = $PSItem
                    }
                }
            }
        }
    }

    if ($Type -eq "domainblocks") {
        $script:blocked = Invoke-Request -Path "domain_blocks" -Method GET

        foreach ($blockacct in $script:blocked.acct) {
            $blockacct = "@" + $blockacct
        }

        $alreadyblocked = $csv | Where-Object { $PSItem -in $script:blocked.acct }
        $notblocked = $csv | Where-Object { $PSItem -notin $script:blocked.acct }

        Write-Verbose "Blocked $($script:blocked.count) domains. $($csv.count) in the csv file. $($alreadyblocked.count) already blocked. Trying to block $($notblocked.count) new domains"

        foreach ($address in $notblocked) {
            try {
                $parms = @{
                    Path = "domain_blocks"
                    Body = @{ domain = $address } | ConvertTo-Json
                }
                $null = Invoke-Request @parms

                [pscustomobject]@{
                    Address = $address
                    Type    = $Type
                    Status  = "Success"
                }
            } catch {
                [pscustomobject]@{
                    Address = $account.acct
                    Type    = $Type
                    Status  = $PSItem
                }
            }
        }
    }

    if ($Type -eq "bookmarks") {
        <#
        # no for now, too slow
        $bookmarks = Invoke-Request -Path "bookmarks" -Method GET
        $alreadybookmarked = $csv | Where-Object { $PSItem -in $bookmarks.uri -or $PSItem -in $bookmarks.url }
        $notbookmarked = $csv | Where-Object { $PSItem -notin $alreadybookmarked }

        Write-Verbose "Bookmarked $($bookmarks.count) posts. $($csv.count) in the csv file. $($alreadybookmarked.count) already bookmarked. Trying to bookmarke $($notbookmarked.count) new posts"
        #>

        foreach ($address in $csv) {
            $id = ([uri]$address).Segments | Select-Object -Last 1
            if ($id) {
                try {
                    $null = Invoke-Request -Path "statuses/$id/bookmark"
                    [pscustomobject]@{
                        Address = $address
                        Type    = $Type
                        Status  = "Success"
                    }
                } catch {
                    [pscustomobject]@{
                        Address = $address
                        Type    = $Type
                        Status  = "$PSItem"
                    }
                }
            }
        }
    }

    if ($Type -eq "lists") {
        $listparms = @{
            Path   = "lists"
            Method = "GET"
        }
        $lists = Invoke-Request @listparms

        $csvlists = $csv | Select-Object -ExpandProperty List -Unique
        # id    title     replies_policy

        foreach ($list in $csvlists) {
            Write-Verbose "Processing $list"
            $thislist = $lists | Where-Object title -eq $list

            if (-not $thislist) {
                Write-Verbose "List $list does not exist, creating"
                $parms = @{
                    Path = "lists"
                    Body = @{ title = $list } | ConvertTo-Json
                }
                # needs a second call, it seems
                $null = Invoke-Request @parms
                $lists = Invoke-Request @listparms
                $thislist = $lists | Where-Object title -eq $list
                $listid = $thislist.id
            } else {
                $listid = $thislist.id
                $existing = Invoke-Request -Path "lists/$listid/accounts" -Method GET
            }

            $members = ($csv | Where-Object List -eq $list).username

            if ($existing) {
                $members = $members | Where-Object { $PSItem -notin $existing.acct }
            }

            if ($members) {
                try {
                    $accounts = Get-Account -UserName $members
                } catch {
                    Write-Warning "$address not found"
                    continue
                }
            }

            try {
                if ($accounts.id) {
                    Write-Verbose "Adding $($accounts.id) to $list"
                    $parms = @{
                        Path = "lists/$listid/accounts"
                        Body = @{ account_ids = $accounts.id } | ConvertTo-Json
                    }
                    $null = Invoke-Request @parms
                    [pscustomobject]@{
                        List    = $list
                        Address = $accounts.username
                        Type    = $Type
                        Status  = "Success"
                    }
                } else {
                    Write-Verbose "No new members to add to $list"
                }
            } catch {
                [pscustomobject]@{
                    List    = $list
                    Address = $accounts.username
                    Type    = $Type
                    Status  = "$PSItem"
                }
            }
        }
    }
}