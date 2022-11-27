function Get-Follower {
    [CmdletBinding()]
    param(
        [psobject[]]$Id = $myid
    )
    $script:link = $null
    Invoke-Request -Path "accounts/$Id/followers" -Method GET -UseWebRequest

    while ($null -ne $script:link) {
        Invoke-Request -Path $script:link -Method GET -UseWebRequest
    }
}

function Get-Following {
    [CmdletBinding()]
    param(
        [psobject[]]$Id = $myid
    )
    $script:link = $null
    Invoke-Request -Path "accounts/$Id/following" -Method GET -UseWebRequest

    while ($null -ne $script:link) {
        Invoke-Request -Path $script:link -Method GET -UseWebRequest
    }
}


function Invoke-Request {
    param(
        [string]$Method = "POST",
        [string]$Server = $env:MASTODON_SERVER,
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Version = "v1",
        [string]$Body,
        [switch]$UseWebRequest
    )

    if ($Path -match "://") {
        $url = $Path
    } else {
        $url = "https://$Server/api/$Version/$Path"
    }

    Write-Verbose "Going to $url"
    $parms = @{
        Uri         = $url
        ErrorAction = "Stop"
        Headers     = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
        Method      = $Method
        Verbose     = $false # too chatty
    }

    if ($Body) {
        $parms.Body = $Body
        $parms.ContentType = "application/json"
    }

    if ($UseWebRequest) {
        $response = Invoke-WebRequest @parms

        if ($response.Headers.Link) {
            $script:link = $response.Headers.Link.Split(";") | Where-Object { $PSitem -match "max_id" } | Select-Object -First 1
            if ($script:link) {
                foreach ($term in "<", ">") {
                    $script:link = $script:link.Replace($term, "")
                }
            }
        } else {
            $script:link = $null
        }

        $response.Content | ConvertFrom-Json -Depth 5
    } else {
        Invoke-RestMethod @parms
    }

    # This keeps it from calling too many times in a 5 minute period
    Start-Sleep -Seconds 1
}


function Get-Account {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$UserName
    )

    foreach ($user in $UserName) {
        $user = $user.Replace("@$env:MASTODON_SERVER", "")
        if ($user.StartsWith("@")) {
            $user = $user.Substring(1)
        }

        $ignored = "youtube.com", "medium.com", "withkoji.com", "counter.social", "twitter.com"
        foreach ($domain in $ignored) {
            if ($user -match $domain) {
                Write-Verbose "User ($user) matched invalid Mastodon domain ($domain). Skipping."
                continue
            }
        }

        $account = $script:accounts | Where-Object acct -eq $user

        if (-not $user.StartsWith("http")) {
            try {
                $address = [mailaddress]$user
                if ($address.Host -eq $Server) {
                    $account = $script:accounts | Where-Object acct -eq $address.User
                    if ($account) {
                        $account
                        continue
                    } else {
                        $user = "https://" + $address.Host + "/@" + $address.User
                    }
                }
            } catch {
                # trying a variety of things because there is no specific
                # search for username, so just ignore it if this didn't work
            }
        }

        $user = $user.Replace("@$Server", "")
        $account = $script:accounts | Where-Object acct -eq $user

        if ($account.id) {
            $account
            continue
        }

        $parms = @{
            Path    = "search?type=accounts&q=$user&resolve=true"
            Method  = "GET"
            Version = "v2"
        }

        $account = Invoke-Request @parms | Select-Object -ExpandProperty accounts

        if ($account) {
            # add to script variable and return
            $null = $script:accounts.Add($account)
            $account
        } else {
            throw "$user not found. The account may not exist, or it may be blocked by your account or Mastodon instance."
        }
    }
}