f (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Run as Administrator!" -ForegroundColor Red
    exit
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHelper {
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
}
"@ -ErrorAction SilentlyContinue
try {
    $handle = [ConsoleHelper]::GetStdHandle(-11)
    $mode = 0
    [ConsoleHelper]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    [ConsoleHelper]::SetConsoleMode($handle, $mode -bor 4) | Out-Null
} catch {}
$pink  = [char]27 + "[38;2;255;182;193m"
$reset = [char]27 + "[0m"
function Write-Pink { param([string]$Text); Write-Host "${pink}${Text}${reset}" }

Write-Pink "Y-sysinfo"
Write-Host ""

Write-Host "Starting sfc /scannow in background..." -ForegroundColor Gray
$sfcJob = Start-Job -ScriptBlock { sfc /scannow 2>&1 }

# BOOT TIME
try {
    $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    Write-Pink "SYSTEM BOOT TIME"
    Write-Host ("  Last Boot : {0}" -f $bootTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    Write-Host ("  Uptime    : {0}d {1:D2}:{2:D2}:{3:D2}" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor White
} catch { Write-Host "  Unable to retrieve boot time" -ForegroundColor Red }

# WINDOWS INSTALLATION
Write-Pink "`nWINDOWS INSTALLATION"
try {
    $raw = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").InstallDate
    if ($raw) {
        $installDate = (Get-Date "1970-01-01 00:00:00").AddSeconds($raw).ToLocalTime()
        Write-Host ("  Install Date : {0}" -f $installDate.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    }
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host ("  OS Version   : {0}" -f $os.Caption) -ForegroundColor White
    Write-Host ("  Build        : {0}" -f $os.BuildNumber) -ForegroundColor White
} catch { Write-Host "  Error reading install info" -ForegroundColor Red }

# DRIVES
$drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -ne 5 }
if ($drives) {
    Write-Pink "`nCONNECTED DRIVES"
    foreach ($d in $drives) { Write-Host ("  {0}: {1}" -f $d.DeviceID, $d.FileSystem) -ForegroundColor Green }
}

# SERVICES
Write-Pink "`nSERVICE STATUS"
$services = @(
    @{Name="SysMain";    DN="SysMain"},
    @{Name="PcaSvc";     DN="Program Compatibility Assistant"},
    @{Name="DPS";        DN="Diagnostic Policy Service"},
    @{Name="EventLog";   DN="Windows Event Log"},
    @{Name="Schedule";   DN="Task Scheduler"},
    @{Name="Bam";        DN="Background Activity Moderator"},
    @{Name="Dusmsvc";    DN="Data Usage"},
    @{Name="Appinfo";    DN="Application Information"},
    @{Name="CDPSvc";     DN="Connected Devices Platform"},
    @{Name="DcomLaunch"; DN="DCOM Server Process Launcher"},
    @{Name="PlugPlay";   DN="Plug and Play"},
    @{Name="wsearch";    DN="Windows Search"},
    @{Name="icssvc";     DN="Mobile Hotspot (icssvc)"}
)
foreach ($svc in $services) {
    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($s) {
        $dn = if ($svc.DN.Length -gt 40) { $svc.DN.Substring(0,37)+"..." } else { $svc.DN }
        if ($svc.Name -eq "icssvc") {
            $col = if ($s.Status -eq "Running") { "Red" } else { "Green" }
            Write-Host ("  {0,-12} {1,-42} {2}" -f $svc.Name, $dn, $s.Status) -ForegroundColor $col
        } elseif ($s.Status -eq "Running") {
            Write-Host ("  {0,-12} {1,-42}" -f $svc.Name, $dn) -ForegroundColor Green -NoNewline
            if ($svc.Name -eq "Bam") { Write-Host " | Enabled" -ForegroundColor White }
            else {
                try {
                    $proc = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" | Select-Object ProcessId
                    if ($proc.ProcessId -gt 0) {
                        $p = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
                        if ($p) { Write-Host (" | {0}" -f $p.StartTime.ToString("HH:mm:ss")) -ForegroundColor White }
                        else { Write-Host " | N/A" -ForegroundColor White }
                    } else { Write-Host " | N/A" -ForegroundColor White }
                } catch { Write-Host " | N/A" -ForegroundColor White }
            }
        } else {
            Write-Host ("  {0,-12} {1,-42} {2}" -f $svc.Name, $dn, $s.Status) -ForegroundColor Red
        }
    } else {
        Write-Host ("  {0,-12} {1,-42} N/A" -f $svc.Name, "Not Found") -ForegroundColor White
    }
}

# REGISTRY
Write-Pink "`nREGISTRY"
$regs = @(
    @{Name="CMD";              Path="HKCU:\Software\Policies\Microsoft\Windows\System";                                                                Key="DisableCMD";               W="Disabled"; S="Available"},
    @{Name="PS Logging";       Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging";                                         Key="EnableScriptBlockLogging"; W="Disabled"; S="Enabled"},
    @{Name="Activities Cache"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                                                                Key="EnableActivityFeed";       W="Disabled"; S="Enabled"},
    @{Name="Prefetch";         Path="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Key="EnablePrefetcher"; W="Disabled"; S="Enabled"}
)
foreach ($r in $regs) {
    $val = Get-ItemProperty -Path $r.Path -Name $r.Key -ErrorAction SilentlyContinue
    Write-Host "  $($r.Name): " -NoNewline -ForegroundColor White
    if ($val -and $val.$($r.Key) -eq 0) { Write-Host $r.W -ForegroundColor Red }
    else { Write-Host $r.S -ForegroundColor Green }
}

# EVENT LOGS
Write-Pink "`nEVENT LOGS"
function Check-EV { param($log,$id,$msg)
    $e = Get-WinEvent -LogName $log -FilterXPath "*[System[EventID=$id]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($e) { Write-Host "  $msg at: " -NoNewline -ForegroundColor White; Write-Host $e.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor White }
    else { Write-Host "  $msg - No records found" -ForegroundColor Green }
}
function Check-EVMulti { param($log,$ids,$msg)
    $xp = ($ids | ForEach-Object { "EventID=$_" }) -join " or "
    $e = Get-WinEvent -LogName $log -FilterXPath "*[System[$xp]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($e) { Write-Host "  $msg (ID:$($e.Id)) at: " -NoNewline -ForegroundColor White; Write-Host $e.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor White }
    else { Write-Host "  $msg - No records found" -ForegroundColor Green }
}
Check-EV      "Application" 3079        "USN Journal cleared"
Check-EVMulti "System"      @(104,1102) "Event Logs cleared"
Check-EV      "System"      1074        "Last PC Shutdown"
Check-EV      "System"      6005        "Event Log Service started"
try {
    $ev = Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Configuration" -FilterXPath "*[System[EventID=400]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($ev) { Write-Host "  Device config changed at: " -NoNewline -ForegroundColor White; Write-Host $ev.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor White }
    else { Write-Host "  Device changes - No records found" -ForegroundColor Green }
} catch { Write-Host "  Device changes - No records found" -ForegroundColor Green }

# USN JOURNAL
Write-Pink "`nUSN JOURNAL"
try {
    $usn = fsutil usn queryjournal C: 2>&1
    if ($usn -match "Invalid") {
        Write-Host "  Status       : DISABLED" -ForegroundColor Red
    } elseif ($usn -match "Usn Journal ID") {
        Write-Host "  Status       : Enabled" -ForegroundColor Green
        $usnClear = Get-WinEvent -LogName "Application" -FilterXPath "*[System[EventID=3079]]" -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($usnClear) { Write-Host "  Last cleared : $($usnClear.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Red }
        else { Write-Host "  Last cleared : Never cleared manually" -ForegroundColor Green }
        $fu = $usn | Select-String "First Usn"
        if ($fu) { Write-Host "  $($fu.Line.Trim())" -ForegroundColor Gray }
    } else { Write-Host "  Status       : Unknown" -ForegroundColor White }
} catch { Write-Host "  Error reading USN Journal" -ForegroundColor Red }

# PREFETCH
$pfPath = "$env:SystemRoot\Prefetch"
if (Test-Path $pfPath) {
    Write-Pink "`nPREFETCH INTEGRITY"
    $files = Get-ChildItem $pfPath -Filter *.pf -Force -ErrorAction SilentlyContinue
    if (-not $files) { Write-Host "  No prefetch files found" -ForegroundColor White }
    else {
        $total = $files.Count; $ht = @{}; $sus = @{}; $hid = @(); $ro = @(); $hidro = @()
        foreach ($f in $files) {
            try {
                $isH = $f.Attributes -band [System.IO.FileAttributes]::Hidden
                $isR = $f.Attributes -band [System.IO.FileAttributes]::ReadOnly
                if ($isH -and $isR) { $hidro += $f; $sus[$f.Name] = "Hidden+ReadOnly" }
                elseif ($isH)       { $hid   += $f; $sus[$f.Name] = "Hidden" }
                elseif ($isR)       { $ro    += $f; $sus[$f.Name] = "ReadOnly" }
                $h = Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue
                if ($h) {
                    if ($ht.ContainsKey($h.Hash)) { $ht[$h.Hash].Add($f.Name) }
                    else { $ht[$h.Hash] = [System.Collections.Generic.List[string]]::new(); $ht[$h.Hash].Add($f.Name) }
                }
            } catch { $sus[$f.Name] = "Error" }
        }
        if ($hidro.Count -gt 0) { Write-Host "  Hidden+ReadOnly: $($hidro.Count)" -ForegroundColor White; $hidro | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor White } }
        if ($hid.Count   -gt 0) { Write-Host "  Hidden: $($hid.Count)" -ForegroundColor White; $hid | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor White } }
        else { Write-Host "  Hidden Files: None" -ForegroundColor Green }
        if ($ro.Count    -gt 0) { Write-Host "  ReadOnly: $($ro.Count)" -ForegroundColor White; $ro | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor White } }
        else { Write-Host "  ReadOnly Files: None" -ForegroundColor Green }
        $dupes = $ht.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($dupes) {
            foreach ($e in $dupes) {
                $e.Value | ForEach-Object { if (-not $sus.ContainsKey($_)) { $sus[$_] = "Duplicate" } }
                Write-Host "  Duplicate: $($e.Value -join ', ')" -ForegroundColor White
            }
        } else { Write-Host "  Duplicates: None" -ForegroundColor Green }
        if ($sus.Count -gt 0) {
            Write-Host "`n  SUSPICIOUS: $($sus.Count)/$total" -ForegroundColor White
            foreach ($e in $sus.GetEnumerator() | Sort-Object Key) { Write-Host "    $($e.Key) : $($e.Value)" -ForegroundColor White }
        } else { Write-Host "`n  Prefetch integrity: Clean ($total files)" -ForegroundColor Green }
    }
} else { Write-Host "`nPREFETCH folder not found" -ForegroundColor Red }

# RECYCLE BIN
Write-Pink "`nRECYCLE BIN"
try {
    $rbPath = "$env:SystemDrive\`$Recycle.Bin"
    if (Test-Path $rbPath) {
        $rbF = Get-Item -LiteralPath $rbPath -Force
        $ufs = Get-ChildItem -LiteralPath $rbPath -Directory -Force -ErrorAction SilentlyContinue
        $all = @(); $lat = $rbF.LastWriteTime
        foreach ($uf in $ufs) {
            if ($uf.LastWriteTime -gt $lat) { $lat = $uf.LastWriteTime }
            $ui = Get-ChildItem -LiteralPath $uf.FullName -File -Force -ErrorAction SilentlyContinue
            if ($ui) {
                $all += $ui
                $lf = $ui | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($lf -and $lf.LastWriteTime -gt $lat) { $lat = $lf.LastWriteTime }
            }
        }
        Write-Host "  Last Modified: $($lat.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
        if ($all.Count -gt 0) {
            Write-Host "  Total Items: $($all.Count)" -ForegroundColor White
            $lt = $all | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Write-Host "  Latest Item: $($lt.Name)" -ForegroundColor Gray
        } else { Write-Host "  Status: Empty" -ForegroundColor Green }
    } else { Write-Host "  Recycle Bin not found" -ForegroundColor White }
} catch { Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red }

# POWERSHELL HISTORY
Write-Pink "`nPOWERSHELL HISTORY"
$hPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
if (Test-Path $hPath) {
    $hf = Get-Item $hPath -Force
    Write-Host "  Last Modified : $($hf.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "  File Size     : $([math]::Round($hf.Length/1024,2)) KB" -ForegroundColor White
    $a = $hf.Attributes
    if ($a -ne "Archive") { Write-Host "  Attributes    : $a" -ForegroundColor White }
    else { Write-Host "  Attributes    : Normal" -ForegroundColor Green }
} else { Write-Host "  History file not found" -ForegroundColor White }

# HOTSPOT / FAKER DETECTION
Write-Pink "`nHOTSPOT / FAKER DETECTION"
$suspAct = @(); $fakerDetected = $false; $fakerIndicators = @(); $networkProfiles = @()
try {
    $po = netsh wlan show profiles
    $pn = $po | Select-String "All User Profile\s+:\s+(.+)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    foreach ($p in $pn) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $isHs = $p -match "Android|iPhone|iPad|Galaxy|Pixel|OnePlus|Xiaomi|DIRECT-|SM-|GT-"
        $networkProfiles += [PSCustomObject]@{ SSID=$p; IsHotspot=$isHs }
    }
    $hsp = $networkProfiles | Where-Object { $_.IsHotspot }
    if ($hsp.Count -gt 0) { Write-Host "  Hotspot profiles: $($hsp.Count)" -ForegroundColor White; $hsp | ForEach-Object { Write-Host "    - $($_.SSID)" -ForegroundColor White } }
    else { Write-Host "  WiFi profiles: no mobile hotspots" -ForegroundColor Green }
} catch {}

try {
    $iface  = netsh wlan show interfaces
    $ssidM  = $iface | Select-String "^\s+SSID\s+:\s+(.+)$"
    $stateM = $iface | Select-String "^\s+State\s+:\s+(.+)$"
    $bssidM = $iface | Select-String "^\s+BSSID\s+:\s+(.+)$"
    $chanM  = $iface | Select-String "^\s+Channel\s+:\s+(.+)$"
    $sigM   = $iface | Select-String "^\s+Signal\s+:\s+(.+)$"
    if ($ssidM -and $stateM) {
        $curSSID  = $ssidM.Matches.Groups[1].Value.Trim()
        $curState = $stateM.Matches.Groups[1].Value.Trim()
        $bssid    = if ($bssidM) { $bssidM.Matches.Groups[1].Value.Trim() } else { "N/A" }
        $chan     = if ($chanM)  { $chanM.Matches.Groups[1].Value.Trim() }  else { "N/A" }
        $sig      = if ($sigM)   { $sigM.Matches.Groups[1].Value.Trim() }   else { "N/A" }
        if ($curState -eq "connected") {
            $isHs = $false; $hsInd = @()
            $pats = @("Android","iPhone","iPad","Galaxy","Pixel","OnePlus","Xiaomi","Huawei","Oppo","Vivo","Realme","Nokia","DIRECT-","SM-[A-Z0-9]","GT-[A-Z0-9]","Redmi","'s iPhone","'s Galaxy","'s Pixel")
            foreach ($pat in $pats) { if ($curSSID -match $pat) { $isHs=$true; $hsInd+="SSID matches: $pat"; break } }
            if ($bssid -ne "N/A") { $sc=$bssid.Substring(1,1); if ($sc -match "[26AEae]") { $isHs=$true; $hsInd+="BSSID locally administered" } }
            try {
                $gw = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.DefaultIPGateway }).DefaultIPGateway | Select-Object -First 1
                if ($gw) {
                    if ($gw -like "192.168.137.*") { $isHs=$true; $fakerDetected=$true; $fakerIndicators+="Windows PC Hotspot gateway (192.168.137.x)"; $hsInd+="Gateway = Windows Mobile Hotspot - FAKER" }
                    elseif ($gw -eq "192.168.43.1") { $isHs=$true; $hsInd+="Gateway = Android hotspot" }
                    elseif ($gw -eq "192.168.49.1") { $isHs=$true; $hsInd+="Gateway = Android hotspot" }
                }
            } catch {}
            Write-Host "  Connected to: $curSSID" -ForegroundColor $(if ($isHs) { "Red" } else { "Green" })
            Write-Host "    BSSID: $bssid | Channel: $chan | Signal: $sig" -ForegroundColor Gray
            if ($isHs) { Write-Host "  WARNING: HOTSPOT DETECTED!" -ForegroundColor Red; $hsInd | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }; $suspAct+="Connected to hotspot: $curSSID" }
        }
    }
} catch {}

try {
    $hn   = netsh wlan show hostednetwork
    $hnSt = $hn | Select-String "Status\s+:\s+(.+)"
    if ($hnSt -and $hnSt.Matches.Groups[1].Value.Trim() -eq "Started") {
        $hnSM = $hn | Select-String 'SSID name\s+:\s+"(.+)"'
        $hnSSID = if ($hnSM) { $hnSM.Matches.Groups[1].Value } else { "Unknown" }
        Write-Host "  WARNING: Hosted Network ACTIVE! SSID: $hnSSID" -ForegroundColor Red
        $suspAct += "Hosted network active: $hnSSID"
    } else { Write-Host "  Hosted Network: Inactive" -ForegroundColor Green }
} catch {}

$ics = Get-Service -Name "icssvc" -ErrorAction SilentlyContinue
if ($ics) {
    if ($ics.Status -eq "Running") { Write-Host "  Mobile Hotspot (icssvc): RUNNING" -ForegroundColor Red; $suspAct+="icssvc running" }
    else { Write-Host "  Mobile Hotspot (icssvc): Stopped" -ForegroundColor Green }
}

try {
    $va = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true -and $_.Description -match "Virtual|Hosted|Wi-Fi Direct|TAP" }
    if ($va) { $va | ForEach-Object { Write-Host "  Virtual adapter: $($_.Description)" -ForegroundColor White }; $suspAct+="$($va.Count) virtual adapter(s)" }
    else { Write-Host "  Virtual adapters: None" -ForegroundColor Green }
} catch {}

# SFC RESULT
Write-Pink "`nSFC SCANNOW"
Write-Host "  Waiting for sfc to finish..." -ForegroundColor White
Wait-Job $sfcJob | Out-Null
$sfcResult = Receive-Job $sfcJob
Remove-Job $sfcJob
$sfcSum = $sfcResult | Where-Object { $_ -match "protection|found|repair|did not find|resource" } | Select-Object -Last 1
if ($sfcSum) {
    $col = if ($sfcSum -match "did not find") { "Green" } else { "White" }
    Write-Host "  Result: $($sfcSum.ToString().Trim())" -ForegroundColor $col
} else { Write-Host "  Result: completed (check CBS.log)" -ForegroundColor White }

# JAVA PROCESSES
Write-Pink "`nJAVA PROCESSES"
$jProcs = Get-Process -Name "java" -ErrorAction SilentlyContinue
if (-not $jProcs) { Write-Host "  No java.exe running" -ForegroundColor Green }
else {
    Write-Host "  Total java processes: $($jProcs.Count)" -ForegroundColor White
    $nsLines = netstat -ano | Select-String "LISTENING|ESTABLISHED"
    foreach ($jp in $jProcs) {
        Write-Host ""
        Write-Host ("  PID {0} | Started: {1}" -f $jp.Id, $jp.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
        try {
            $cl = (Get-WmiObject Win32_Process -Filter "ProcessId=$($jp.Id)").CommandLine
            if ($cl) {
                $sh = if ($cl.Length -gt 120) { $cl.Substring(0,117)+"..." } else { $cl }
                Write-Host "    CMD: $sh" -ForegroundColor Gray
            }
        } catch {}
        $pp = $nsLines | Where-Object { $_ -match "\s+$($jp.Id)\s*$" }
        if ($pp) {
            Write-Host "    Ports:" -ForegroundColor White
            $pp | ForEach-Object { $l=$_.Line.Trim(); $c=if ($l -match ":25565") {"Red"} else {"White"}; Write-Host "      $l" -ForegroundColor $c }
        } else { Write-Host "    Ports: none found" -ForegroundColor Gray }
    }
}

# PORT 25565
Write-Pink "`nPORT 25565 (Minecraft)"
$ns25 = netstat -ano | Select-String ":25565"
if ($ns25) { Write-Host "  Port 25565 ACTIVE:" -ForegroundColor Red; $ns25 | ForEach-Object { Write-Host "    $($_.Line.Trim())" -ForegroundColor White } }
else { Write-Host "  Port 25565: Not in use" -ForegroundColor Green }

# SUMMARY
Write-Host "`n============================================================" -ForegroundColor DarkGray
Write-Pink "  SUMMARY"
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host "  Suspicious activities : $($suspAct.Count)" -ForegroundColor $(if ($suspAct.Count -gt 0) {"Red"} else {"Green"})
Write-Host "  Faker detected        : $(if ($fakerDetected) {'YES'} else {'No'})" -ForegroundColor $(if ($fakerDetected) {"Red"} else {"Green"})
Write-Host "  Hotspot profiles      : $(($networkProfiles | Where-Object {$_.IsHotspot}).Count)" -ForegroundColor White
if ($suspAct.Count -gt 0) { Write-Host "`n  Warnings:" -ForegroundColor Red; $suspAct | ForEach-Object { Write-Host "    - $_" -ForegroundColor White } }
if ($fakerIndicators.Count -gt 0) { Write-Host "`n  Faker indicators:" -ForegroundColor Red; $fakerIndicators | ForEach-Object { Write-Host "    - $_" -ForegroundColor White } }

Write-Host "`nCheck complete. @sweetvata" -ForegroundColor DarkGray
Write-Host ""
