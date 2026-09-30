<#
.SYNOPSIS
    Wrapper: runs Get-MA-RoundTrips.ps1 then emails the report files.
    Designed to be called by Windows Task Scheduler daily.
#>
# --- Ensure Python is on PATH ---
$env:Path += ";C:\Users\alexb\AppData\Local\Programs\Python\Python313;C:\Users\alexb\AppData\Local\Programs\Python\Python313\Scripts"

# --- Paths ---
$ScriptDir = "C:\Users\alexb\OneDrive\Documents\NinjaTrader 8\log"
$AnalysisScript = Join-Path $ScriptDir "Get-MA-RoundTrips.ps1"
$ReportDate = Get-Date -Format "MM-dd-yyyy"
$TxtReport  = Join-Path $ScriptDir "MARoundTripsAnalysis-$ReportDate.txt"
$HtmlReport = Join-Path $ScriptDir "MARoundTripsAnalysis-$ReportDate.html"
$PdfReport  = Join-Path $ScriptDir "MARoundTripsAnalysis-$ReportDate.pdf"
$TxtReportDisc  = Join-Path $ScriptDir "DISCRoundTripsAnalysis-$ReportDate.txt"
$HtmlReportDisc = Join-Path $ScriptDir "DISCRoundTripsAnalysis-$ReportDate.html"
$PdfReportDisc  = Join-Path $ScriptDir "DISCRoundTripsAnalysis-$ReportDate.pdf"

# --- Run analysis ---
Write-Host "Running TTP analysis..." -ForegroundColor Cyan
& $AnalysisScript

# --- VPS name from local IP ---
$vpsMap = @{
    "104.237.203.83"   = "VPS1"
    "205.234.153.21"  = "VPS2"
    "64.44.56.21"     = "VPS3"
    "172.245.253.135" = "VPS4"
}
# $vpsName = ""
$vpsName = "[Laptop] "
$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
       Select-Object -ExpandProperty IPAddress
foreach ($ip in $ips) {
    if ($vpsMap.ContainsKey($ip)) { $vpsName = "[$($vpsMap[$ip])] "; break }
}

# --- Email config ---
$EmailTo      = @("alex.boutov@gmail.com")
# $EmailTo      = @("alex.boutov@gmail.com", "615thstreetdev@gmail.com", "olga.boutov@gmail.com")
# Uncomment to add Niki:
# $EmailTo      = @("alex.boutov@gmail.com", "615thstreetdev@gmail.com")
$EmailFrom    = "nds.ttp.reports@gmail.com"
$EmailAppPass = "vzxw howm zkws smrt"
$SmtpServer   = "smtp.gmail.com"
$SmtpPort     = 587

# --- Build attachment list ---
$Attachments = @()
if (Test-Path $PdfReport)      { $Attachments += $PdfReport }
if (Test-Path $HtmlReport)     { $Attachments += $HtmlReport }
if (Test-Path $TxtReport)      { $Attachments += $TxtReport }
if (Test-Path $PdfReportDisc)  { $Attachments += $PdfReportDisc }
if (Test-Path $HtmlReportDisc) { $Attachments += $HtmlReportDisc }
if (Test-Path $TxtReportDisc)  { $Attachments += $TxtReportDisc }

if ($Attachments.Count -eq 0) {
    Write-Warning "No report files found for $ReportDate. Skipping email."
    exit 1
}

# --- Build email body: HTML <pre> with monospace font so columns align in mail clients ---
$Subject = ("$vpsName" + "Trade Analysis Report - $ReportDate").Trim()

$BodyLines = [System.Collections.Generic.List[string]]::new()
$BodyLines.Add("Trades Analysis Report - $ReportDate")
$BodyLines.Add("")

# Returns a section's lines: from its "=== HEADER ..." line up to the next "=== " header.
# Header match is by prefix, tolerating the "from <date> to <date>" suffix.
function Get-ReportSection([string[]]$lines, [string]$header) {
    $s = -1; $e = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($s -lt 0) {
            if ($lines[$i] -like "$header*") { $s = $i }
        } elseif ($lines[$i] -like '=== *') { $e = $i; break }
    }
    if ($s -lt 0) { return @() }
    return $lines[$s..($e - 1)]
}

# Returns the LAST "=== INDIVIDUAL TRADES - <date> ===" section (most recent trading day),
# from its header through the line before the next "=== " header, trailing blanks trimmed.
function Get-LastDayTrades([string]$txtPath) {
    $all = @(Get-Content $txtPath)
    $s = -1
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($all[$i] -like '=== INDIVIDUAL TRADES*') { $s = $i }
    }
    if ($s -lt 0) { return @() }
    $e = $all.Count
    for ($i = $s + 1; $i -lt $all.Count; $i++) {
        if ($all[$i] -like '=== *') { $e = $i; break }
    }
    $sec = @($all[$s..($e - 1)])
    while ($sec.Count -gt 0 -and $sec[$sec.Count - 1].Trim() -eq '') { $sec = @($sec[0..($sec.Count - 2)]) }
    return $sec
}

# Given the trade-row lines returned by Get-LastDayTrades, sums PnL_$ per instrument
# using the fixed-width columns the report writer uses (Instrument at 24..36, PnL_$ at 82..92).
function Get-InstrumentTotals([string[]]$tradeLines) {
    $totals = [ordered]@{}
    foreach ($ln in $tradeLines) {
        if ($ln.Length -lt 92 -or $ln -notmatch '^\d{4}-\d{2}-\d{2}\s') { continue }
        $instr  = $ln.Substring(24, 12).Trim()
        $pnlStr = $ln.Substring(82, 10).Trim()
        if ([string]::IsNullOrWhiteSpace($instr) -or [string]::IsNullOrWhiteSpace($pnlStr)) { continue }
        $isNeg = $pnlStr -match '^\('
        $num = 0.0
        if (-not [double]::TryParse(($pnlStr -replace '[()$,]', ''), [ref]$num)) { continue }
        if ($isNeg) { $num = -[math]::Abs($num) }
        if (-not $totals.Contains($instr)) { $totals[$instr] = 0.0 }
        $totals[$instr] += $num
    }
    return $totals
}

# Formats a PnL total using the report's own accounting style: parens for negative, no sign for positive/zero.
function Format-PnLTotal([double]$val) {
    if ($val -lt 0) { return "(" + [math]::Abs($val).ToString("N0") + ")" }
    return $val.ToString("N0")
}

# Extracts the email-body portion of one report file:
# everything from the top through the end of TIME OF DAY ANALYSIS,
# plus the per-instrument daily equity curves.
function Get-ReportBodyLines([string]$txtPath) {
    $out = [System.Collections.Generic.List[string]]::new()
    $allLines = @(Get-Content $txtPath)
    $endIdx = $allLines.Count
    $todIdx = -1
    for ($i = 0; $i -lt $allLines.Count; $i++) {
        if ($todIdx -lt 0) {
            if ($allLines[$i] -like '=== TIME OF DAY ANALYSIS*') { $todIdx = $i }
        } elseif ($allLines[$i] -like '=== *') {
            $endIdx = $i
            break
        }
    }
    if ($todIdx -lt 0) { $endIdx = [Math]::Min(30, $allLines.Count) }  # fallback: first 30 lines
    foreach ($ln in $allLines[0..($endIdx - 1)]) { $out.Add($ln) }

    # Plus the per-instrument daily equity curves (with win/loss-by-hour subsections)
    foreach ($ln in (Get-ReportSection $allLines '=== DAILY EQUITY CURVE BY INSTRUMENT')) { $out.Add($ln) }

    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
    return $out
}

# --- Last trading day's individual trades, at the very top of the body ---
foreach ($src in @(@{ Label = "MA STRATEGY";  Path = $TxtReport },
                   @{ Label = "DISCRETIONARY"; Path = $TxtReportDisc })) {
    if (Test-Path $src.Path) {
        $dayTrades = @(Get-LastDayTrades $src.Path)
        if ($dayTrades.Count -gt 0) {
            $BodyLines.Add("[$($src.Label)]")
            foreach ($ln in $dayTrades) { $BodyLines.Add($ln) }
            $BodyLines.Add("")

            $totals = Get-InstrumentTotals $dayTrades
            if ($totals.Count -gt 0) {
                $BodyLines.Add("  Daily PnL by instrument:")
                foreach ($instr in $totals.Keys) {
                    $BodyLines.Add(("  {0,-12} {1,10}" -f $instr, (Format-PnLTotal $totals[$instr])))
                }
                $grand = ($totals.Values | Measure-Object -Sum).Sum
                $BodyLines.Add(("  {0,-12} {1,10}" -f "TOTAL", (Format-PnLTotal $grand)))
                $BodyLines.Add("")
            }
        }
    }
}

# --- Section 1: TTP bot ---
$BodyLines.Add("############################################################")
$BodyLines.Add("#                         MA STRATEGY                      #")
$BodyLines.Add("############################################################")
$BodyLines.Add("")
if (Test-Path $TxtReport) {
    foreach ($ln in (Get-ReportBodyLines $TxtReport)) { $BodyLines.Add($ln) }
} else {
    $BodyLines.Add("(No TTP bot trades in this period.)")
}
$BodyLines.Add("")

# --- Section 2: Discretionary ---
$BodyLines.Add("############################################################")
$BodyLines.Add("#                     DISCRETIONARY                        #")
$BodyLines.Add("############################################################")
$BodyLines.Add("")
if (Test-Path $TxtReportDisc) {
    foreach ($ln in (Get-ReportBodyLines $TxtReportDisc)) { $BodyLines.Add($ln) }
} else {
    $BodyLines.Add("(No discretionary trades in this period.)")
}
$BodyLines.Add("")
$BodyLines.Add("(Full reports with charts attached as PDF, TXT, and HTML)")

# --- Colorize: negatives (accounting parens) red bold, positives green bold ---
# Money columns are located by position within known data-row shapes:
#   TOD rows       "07:00  68 ..."      -> tokens 6,7,8 (PnL_$, AvgWin_$, AvgLoss_$)
#   daily rows     "  2026-07-09 ..."   -> tokens 3,4   (DayPnL_$, Cumulative_$)
#   hourly subrows "    07:00  2 ..."   -> tokens 3,4   (PnL_$, AvgPnL_$)
$redStyle   = 'color:#c62828;font-weight:bold;'
$greenStyle = 'color:#2e7d32;font-weight:bold;'
function Colorize-Line([string]$line) {
    $esc = [System.Net.WebUtility]::HtmlEncode($line)
    # Per-instrument daily PnL total row (e.g. "  NQ DEC26         4,301" or "  TOTAL        (75)")
    if ($line -match '^\s\s\S.*\s+(\([\d,\.]+\)|-?[\d,\.]+)\s*$' -and $line -notmatch '^\s\sDaily PnL by instrument:') {
        $pv = $Matches[1]
        if ($pv -match '^\(') { return "<span style=""$script:redStyle"">$esc</span>" }
        $num = 0.0
        if ([double]::TryParse(($pv -replace ',', ''), [ref]$num) -and $num -gt 0) {
            return "<span style=""$script:greenStyle"">$esc</span>"
        }
        return $esc
    }
    # Individual trade row: color the whole row by the sign of PnL_$ (last numeric column)
    if ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}:\d{3}\s') {
        if ($line -match '(\([\d,\.]+\)|-?[\d,\.]+)\s*\*?\s*$') {
            $pv = $Matches[1]
            if ($pv -match '^\(') { return "<span style=""$script:redStyle"">$esc</span>" }
            $num = 0.0
            if ([double]::TryParse(($pv -replace ',', ''), [ref]$num) -and $num -gt 0) {
                return "<span style=""$script:greenStyle"">$esc</span>"
            }
        }
        return $esc
    }
    $targets = $null
    if     ($line -match '^\d{2}:00\s')            { $targets = @(5, 6, 7) }
    elseif ($line -match '^\s+\d{4}-\d{2}-\d{2}\s') { $targets = @(2, 3) }
    elseif ($line -match '^\s+\d{2}:00\s')          { $targets = @(2, 3) }
    if ($targets) {
        $toks = [regex]::Matches($esc, '\S+')
        foreach ($ti in ($targets | Sort-Object -Descending)) {
            if ($ti -ge $toks.Count) { continue }
            $tok = $toks[$ti].Value
            $style = $null
            if     ($tok -match '^\(\d+(\.\d+)?\)$')                        { $style = $script:redStyle }
            elseif ($tok -match '^\d+(\.\d+)?$' -and [double]$tok -ne 0)    { $style = $script:greenStyle }
            if ($style) {
                $esc = $esc.Substring(0, $toks[$ti].Index) +
                       "<span style=""$style"">$tok</span>" +
                       $esc.Substring($toks[$ti].Index + $tok.Length)
            }
        }
        return $esc
    }
    # Non-table lines (summary, pipe sections): color $-prefixed values as before
    return [regex]::Replace($esc, '\$(-?)(\d+(?:\.\d+)?)', {
        param($m)
        if ($m.Groups[1].Value -eq '-') {
            "<span style=""color:#c62828;"">$($m.Value)</span>"
        } elseif ([double]$m.Groups[2].Value -ne 0) {
            "<span style=""color:#2e7d32;"">$($m.Value)</span>"
        } else {
            $m.Value
        }
    })
}

$BodyColored = (($BodyLines | ForEach-Object { Colorize-Line $_ }) -join "`r`n")
$Body = "<pre style=""font-family:Consolas,'Courier New',monospace; font-size:13px;"">$BodyColored</pre>"

# --- Send email ---
$smtpCred = New-Object System.Management.Automation.PSCredential(
    $EmailFrom,
    (ConvertTo-SecureString $EmailAppPass -AsPlainText -Force)
)

$mailParams = @{
    From        = $EmailFrom
    To          = $EmailTo
    Subject     = $Subject
    Body        = $Body
    BodyAsHtml  = $true
    SmtpServer  = $SmtpServer
    Port        = $SmtpPort
    UseSsl      = $true
    Credential  = $smtpCred
    Attachments = $Attachments
}

try {
    Send-MailMessage @mailParams -ErrorAction Stop
    Write-Host "Email sent to: $($EmailTo -join ', ')" -ForegroundColor Green
} catch {
    Write-Error "Failed to send email: $_"
    exit 1
}

# --- Cleanup: remove report files older than 7 days ---
Get-ChildItem -Path $ScriptDir -Filter "*RoundTripsAnalysis-*" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "Cleaned up: $($_.Name)" -ForegroundColor DarkGray
    }
