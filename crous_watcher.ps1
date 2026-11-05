<#
.SYNOPSIS
    CROUS Housing Real-Time Watcher
    Checks CROUS housing search every few seconds and sends desktop notifications (macOS & Windows) on any change.
#>

param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot "config.json"),
    [string]$StateFile = (Join-Path $PSScriptRoot "crous_state.json"),
    [string]$LogFile = (Join-Path $PSScriptRoot "crous_watcher.log")
)

$IsMac = $IsMacOS -or ($PSVersionTable.OS -match "Darwin") -or ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX))
$IsWin = $IsWindows -or ($env:OS -eq "Windows_NT")

# Default configuration
$SearchUrl = "https://trouverunlogement.lescrous.fr/tools/48/search?bounds=1.5573120117187502_49.384160800744986_3.0926513671875004_47.92002350993272"
$IntervalSeconds = 10
$PlaySound = $true
$OpenBrowserOnNew = $true
$NtfyTopic = "crous-zak-2729fc55"
$DiscordWebhookUrl = "https://discord.com/api/webhooks/1567918927160283236/StItho8eOwd8Y9A4BQ1T88-xKG8NUgvFtJd8yWdkmfrAUOchvabdHO_ApwwF72WlaF22"

# Load config if present
if (Test-Path $ConfigFile) {
    try {
        $cfg = Get-Content $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($cfg.searchUrl) { $SearchUrl = $cfg.searchUrl }
        if ($cfg.checkIntervalSeconds) { $IntervalSeconds = [int]$cfg.checkIntervalSeconds }
        if ($null -ne $cfg.playSound) { $PlaySound = [bool]$cfg.playSound }
        if ($null -ne $cfg.openBrowserOnNewListing) { $OpenBrowserOnNew = [bool]$cfg.openBrowserOnNewListing }
        if ($cfg.ntfyTopic) { $NtfyTopic = [string]$cfg.ntfyTopic }
        if ($cfg.discordWebhookUrl) { $DiscordWebhookUrl = [string]$cfg.discordWebhookUrl }
    } catch {
        Write-Warning "Could not parse config.json, using defaults."
    }
}

# Windows Notification APIs
if ($IsWin) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    } catch {}
}

function Open-ListingUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return }
    try {
        if ($IsMac) {
            & /usr/bin/open $Url
        } else {
            Start-Process $Url
        }
    } catch {
        Write-Warning "Failed to open browser for URL: $Url"
    }
}

function Send-Toast {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Url = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($DiscordWebhookUrl)) {
        try {
            $discordContent = "@everyone 🚨 **$Title**`n$Message"
            if ($Url) { $discordContent += "`n👉 **Lien direct :** $Url" }
            $payload = @{ username = "CROUS Housing Monitor"; content = $discordContent } | ConvertTo-Json -Compress
            & curl -s -X POST $DiscordWebhookUrl -H "Content-Type: application/json" -d $payload | Out-Null
        } catch {
            Write-Warning "Discord webhook failed: $($_.Exception.Message)"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($NtfyTopic)) {
        try {
            $asciiTitle = ($Title -replace '[^\x20-\x7E]', '').Trim()
            if (-not $asciiTitle) { $asciiTitle = "CROUS Alert" }
            $curlArgs = @("-s", "-X", "POST", "https://ntfy.sh/$NtfyTopic", "-H", "Title: $asciiTitle", "-H", "Priority: max", "-H", "Tags: house,rotating_light", "-d", $Message)
            if ($Url) {
                $curlArgs += @("-H", "Click: $Url", "-H", "Actions: view, Ouvrir le logement, $Url, clear=true")
            }
            & curl @curlArgs | Out-Null
        } catch {
            Write-Warning "Phone push (ntfy) failed: $($_.Exception.Message)"
        }
    }

    if ($IsMac) {
        try {
            $cleanTitle = $Title -replace '"', '\"' -replace "`r|`n", " "
            $cleanMsg = $Message -replace '"', '\"' -replace "`r|`n", " — "
            $script = "display notification `"$cleanMsg`" with title `"$cleanTitle`""
            if ($PlaySound) {
                $script += " sound name `"Glass`""
            }
            & /usr/bin/osascript -e $script | Out-Null
            if ($PlaySound -and (Test-Path "/System/Library/Sounds/Glass.aiff")) {
                Start-Process -FilePath "/usr/bin/afplay" -ArgumentList "/System/Library/Sounds/Glass.aiff" -NoNewWindow -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "macOS notification failed: $($_.Exception.Message)"
        }
        return
    }

    try {
        if ($PlaySound) {
            [System.Media.SystemSounds]::Exclamation.Play()
        }

        $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
        $escapedMessage = [System.Security.SecurityElement]::Escape($Message)

        $xml = @"
<toast activationType="protocol" launch="$Url">
    <visual>
        <binding template="ToastGeneric">
            <text>$escapedTitle</text>
            <text>$escapedMessage</text>
        </binding>
    </visual>
    <audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@
        $xmlDoc = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $xmlDoc.LoadXml($xml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDoc)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe")
        $notifier.Show($toast)
    } catch {
        Write-Warning "Toast notification failed: $($_.Exception.Message)"
    }
}

function Log-Message {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $line -Encoding utf8
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      CROUS HOUSING REAL-TIME WATCHER                     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Log-Message "Monitoring CROUS listings every $IntervalSeconds seconds..." Cyan
Log-Message "Auto-open browser on new listing: $OpenBrowserOnNew" Gray
Log-Message "Search URL: $SearchUrl" Gray
Log-Message "==========================================================" Cyan

# Load state if exists
$knownListings = @{}
$isFirstRun = -not (Test-Path $StateFile)

if (-not $isFirstRun) {
    try {
        $saved = Get-Content $StateFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($saved.listings) {
            foreach ($prop in $saved.listings.PSObject.Properties) {
                $knownListings[$prop.Name] = $prop.Value
            }
        } elseif ($saved.ids) {
            foreach ($id in $saved.ids) {
                $knownListings[$id.ToString()] = @{ id = $id.ToString() }
            }
        }
        Log-Message "Loaded $($knownListings.Count) existing listing(s) from state cache." Yellow
    } catch {
        Log-Message "Creating new state cache." Yellow
    }
}

$iteration = 0
$consecutiveErrors = 0

while ($true) {
    $iteration++
    try {
        # Fetch page HTML with the platform's curl command (includes retry for transient network failures)
        $rawOutput = & curl -s -L --retry 2 --retry-delay 1 --max-time 15 -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -H "Accept: text/html,application/xhtml+xml,application/xml" $SearchUrl
        $content = $rawOutput -join "`n"

        if ([string]::IsNullOrWhiteSpace($content) -or $content.Length -lt 1000) {
            throw "Empty or invalid response from CROUS server (length: $($content.Length))"
        }

        # Extract search results JSON
        $jsonMatch = [regex]::Match($content, 'data-url="[^"]*search[^"]*"[^>]*>\s*(\{.*?\})\s*</script>')
        if (-not $jsonMatch.Success) {
            throw "Could not find search results script block in HTML"
        }

        $rawJson = $jsonMatch.Groups[1].Value
        $data = $rawJson | ConvertFrom-Json
        $searchResults = $data.body | ConvertFrom-Json

        $total = $searchResults.results.total.value
        $items = $searchResults.results.items

        # Build current listings map
        $currentListings = @{}
        foreach ($item in $items) {
            $id = $item.id.ToString()
            $label = $item.residence.label
            $rentMin = ($item.occupationModes | ForEach-Object { $_.rent.min } | Sort-Object | Select-Object -First 1)
            $rentEur = if ($rentMin) { [math]::Round($rentMin / 100, 2) } else { 0 }
            $area = "$($item.area.min)-$($item.area.max) m²"
            $address = $item.residence.address
            $url = "https://trouverunlogement.lescrous.fr/tools/48/accommodations/$id"

            $currentListings[$id] = @{
                id = $id
                label = $label
                rent = $rentEur
                area = $area
                address = $address
                url = $url
            }
        }

        # On very first run, record baseline without false-positive alert
        if ($isFirstRun) {
            $knownListings = $currentListings
            $isFirstRun = $false
            Log-Message "Initial baseline established: $total listing(s) found." Green
            foreach ($item in $currentListings.Values) {
                Log-Message "  - $($item.label) ($($item.rent) EUR) -> $($item.address)" Gray
            }
            
            $stateObj = @{
                lastUpdate = (Get-Date -Format 'o')
                total = $total
                ids = @($currentListings.Keys | Sort-Object)
                listings = $currentListings
            }
            $stateObj | ConvertTo-Json -Depth 5 | Set-Content -Path $StateFile -Encoding utf8
        } else {
            # Compare against known listings
            $newIds = @($currentListings.Keys | Where-Object { -not $knownListings.ContainsKey($_) })
            $removedIds = @($knownListings.Keys | Where-Object { -not $currentListings.ContainsKey($_) })

            if ($newIds.Count -gt 0 -or $removedIds.Count -gt 0) {
                Log-Message "**********************************************************" Magenta
                Log-Message ">>> DIFFERENCE DETECTED! Total listings: $total <<<" Magenta
                Log-Message "**********************************************************" Magenta

                # 1. New listings detected
                foreach ($id in $newIds) {
                    $item = $currentListings[$id]
                    $msg = "$($item.label) | $($item.rent) EUR/mo | $($item.area)`n$($item.address)"
                    Log-Message "[NEW HOUSING AVAILABLE] $msg" Green
                    Send-Toast -Title "🏠 NEW CROUS HOUSING AVAILABLE!" -Message $msg -Url $item.url

                    if ($OpenBrowserOnNew) {
                        Open-ListingUrl -Url $item.url
                    }
                }

                # 2. Removed listings
                foreach ($id in $removedIds) {
                    $oldItem = $knownListings[$id]
                    $oldLabel = if ($oldItem.label) { $oldItem.label } else { "Listing #$id" }
                    Log-Message "[LISTING REMOVED / TAKEN] $oldLabel" Red
                    Send-Toast -Title "❌ CROUS Listing Removed" -Message "$oldLabel is no longer available."
                }

                # Update state
                $knownListings = $currentListings
                $stateObj = @{
                    lastUpdate = (Get-Date -Format 'o')
                    total = $total
                    ids = @($currentListings.Keys | Sort-Object)
                    listings = $currentListings
                }
                $stateObj | ConvertTo-Json -Depth 5 | Set-Content -Path $StateFile -Encoding utf8
            } else {
                # Normal check
                if ($iteration % 6 -eq 1) { # Every ~60s
                    Log-Message "Check #($iteration): $total listing(s) active. No changes." DarkGray
                }
            }
        }

        $consecutiveErrors = 0
    } catch {
        $consecutiveErrors++
        Log-Message "Check #($iteration) Network warning: $($_.Exception.Message)" Yellow
        if ($consecutiveErrors -eq 10) {
            Send-Toast -Title "CROUS Monitor Alert" -Message "10 consecutive connection failures to CROUS site."
        }
    }

    Start-Sleep -Seconds $IntervalSeconds
}
