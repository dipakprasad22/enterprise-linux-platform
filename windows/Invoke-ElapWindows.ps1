# ═══════════════════════════════════════════════════════════════
# ELAP Windows Automation Suite
# File: windows/Invoke-ElapWindows.ps1
# Part of: enterprise-linux-platform
#
# Adds Windows automation to the ELAP platform
# ═══════════════════════════════════════════════════════════════

#Requires -Version 5.1

<#
.SYNOPSIS
    ELAP Windows Infrastructure Automation Suite

.DESCRIPTION
    Extends ELAP to Windows environments:
    - AD user provisioning and offboarding
    - Security hardening (CIS Level 1)
    - IIS deployment automation
    - Windows patch status reporting
    - Performance baseline collection

.PARAMETER Action
    Action to perform: Provision, Harden, Report, Monitor, PatchReport

.EXAMPLE
    .\Invoke-ElapWindows.ps1 -Action Report -Servers @('WEB01','WEB02')
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Provision','Harden','Report','Monitor','PatchReport','ADReport')]
    [string]$Action,

    [string[]]$Servers = @($env:COMPUTERNAME),
    [string]$Environment = 'Production',
    [switch]$DryRun,
    [string]$OutputPath = "C:\ELAP\Reports"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$LogFile = Join-Path $OutputPath "elap-windows-$(Get-Date -Format 'yyyyMMdd-HHmm').log"

function Write-ElapLog {
    param([string]$Level='INFO', [string]$Message)
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    Add-Content $LogFile -Value $entry
    $c = switch($Level) {'ERROR'{'Red'}'WARN'{'Yellow'}'SUCCESS'{'Green'}default{'Cyan'}}
    Write-Host $entry -ForegroundColor $c
}

# ── Patch Report ──────────────────────────────────────────────
function Get-PatchReport {
    param([string[]]$Computers)

    $results = @()

    foreach ($computer in $Computers) {
        Write-ElapLog "INFO" "Collecting patch status: $computer"
        try {
            $data = Invoke-Command -ComputerName $computer -ScriptBlock {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $pending  = $searcher.Search("IsInstalled=0 and Type='Software'")

                $os = Get-WmiObject Win32_OperatingSystem
                $lastBoot = $os.ConvertToDateTime($os.LastBootUpTime)

                $pendingReboot = Test-Path `
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

                [PSCustomObject]@{
                    ComputerName   = $env:COMPUTERNAME
                    OS             = $os.Caption
                    LastBoot       = $lastBoot
                    PendingUpdates = $pending.Updates.Count
                    CriticalCount  = ($pending.Updates | Where-Object {
                                         $_.MsrcSeverity -eq 'Critical'}).Count
                    PendingReboot  = $pendingReboot
                    UpdatesPending = $pending.Updates | Select-Object -First 5 |
                                     ForEach-Object { $_.Title }
                }
            }
            $results += $data
        } catch {
            Write-ElapLog "WARN" "Cannot reach $computer : $_"
            $results += [PSCustomObject]@{
                ComputerName   = $computer
                OS             = "Unreachable"
                PendingUpdates = -1
                CriticalCount  = -1
                PendingReboot  = $null
            }
        }
    }

    return $results
}

# ── HTML Report Generator ─────────────────────────────────────
function New-ElapHtmlReport {
    param(
        [string]$Title,
        [PSCustomObject[]]$Data,
        [string]$OutputFile
    )

    $tableHtml = $Data | ConvertTo-Html -Fragment -As Table

    $html = @"
<!DOCTYPE html>
<html>
<head>
<title>$Title</title>
<style>
  body { font-family:Segoe UI,sans-serif; background:#1a1a2e; color:#e0e0e0; padding:20px; }
  h1   { color:#60a5fa; }
  h2   { color:#94a3b8; margin-top:20px; }
  table { width:100%; border-collapse:collapse; background:#1e293b; border-radius:8px;
          overflow:hidden; margin:12px 0; }
  th   { background:#0f172a; padding:10px; text-align:left; color:#64748b; font-size:12px; }
  td   { padding:10px; border-bottom:1px solid #0f172a; font-size:13px; }
  .good { color:#22c55e; } .warn { color:#f59e0b; } .crit { color:#ef4444; }
</style>
</head>
<body>
<h1>$Title</h1>
<p>Generated: $(Get-Date) | By: $env:USERNAME@$env:USERDOMAIN</p>
<h2>Results</h2>
$tableHtml
</body>
</html>
"@

    $html | Out-File $OutputFile -Encoding UTF8
    Write-ElapLog "SUCCESS" "Report: $OutputFile"
}

# ── Main dispatcher ───────────────────────────────────────────
Write-ElapLog "INFO" "ELAP Windows Suite | Action: $Action | Env: $Environment"

switch ($Action) {
    'PatchReport' {
        $patchData = Get-PatchReport -Computers $Servers
        $outFile   = Join-Path $OutputPath "patch-report-$(Get-Date -Format 'yyyyMMdd').html"
        New-ElapHtmlReport `
            -Title "ELAP Windows Patch Status Report — $Environment" `
            -Data $patchData `
            -OutputFile $outFile
        Invoke-Item $outFile
    }

    'Monitor' {
        foreach ($server in $Servers) {
            Write-ElapLog "INFO" "Monitoring: $server"
            Get-WindowsPerformanceBaseline -ComputerName $server
        }
    }

    'Report' {
        $allHealth = @()
        foreach ($server in $Servers) {
            Write-ElapLog "INFO" "Collecting health: $server"
            try {
                $h = Get-ServerHealth -ComputerName $server
                $allHealth += $h
            } catch {
                Write-ElapLog "WARN" "Cannot collect from $server : $_"
            }
        }
        $outFile = Join-Path $OutputPath "health-report-$(Get-Date -Format 'yyyyMMdd').html"
        New-ElapHtmlReport `
            -Title "ELAP Windows Infrastructure Health — $Environment" `
            -Data ($allHealth | Select-Object ComputerName, OS, CPULoad, FreeRAMGB, PendingReboot) `
            -OutputFile $outFile
        Invoke-Item $outFile
    }

    'ADReport' {
        if (Get-Module -ListAvailable -Name ActiveDirectory) {
            Import-Module ActiveDirectory
            $adData = Get-ADComputer -Filter {
                OperatingSystem -like "*Windows Server*"
            } -Properties OperatingSystem, OperatingSystemVersion,
                           LastLogonDate, Description |
                Select-Object Name, OperatingSystem,
                              LastLogonDate, Description |
                Sort-Object Name

            $outFile = Join-Path $OutputPath "ad-computer-report-$(Get-Date -Format 'yyyyMMdd').html"
            New-ElapHtmlReport `
                -Title "ELAP Active Directory Computer Inventory" `
                -Data $adData `
                -OutputFile $outFile
            Invoke-Item $outFile
        } else {
            Write-ElapLog "WARN" "ActiveDirectory module not available — install RSAT"
        }
    }
}

Write-ElapLog "SUCCESS" "ELAP Windows Suite completed"
Write-ElapLog "INFO" "Log: $LogFile"