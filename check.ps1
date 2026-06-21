# ============================================================
#  check.ps1 — полная диагностика системы (by praiselily)
#  Запускать от имени Администратора
# ============================================================

$isAdmin = [System.Security.Principal.WindowsPrincipal]::new(
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`n[ОШИБКА] Нужны права Администратора!" -ForegroundColor Red
    exit
}

Write-Host "Y-sysinfo" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# UPTIME
# ============================================================
try {
    $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    Write-Host "SYSTEM BOOT TIME" -ForegroundColor Cyan
    Write-Host ("  Last Boot: {0}" -f $bootTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    Write-Host ("  Uptime: {0} days, {1:D2}:{2:D2}:{3:D2}" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds) -ForegroundColor White
} catch {
    Write-Host "  Unable to retrieve boot time" -ForegroundColor Red
}

# ============================================================
# ДАТА УСТАНОВКИ WINDOWS
# ============================================================
Write-Host "`nWINDOWS INSTALLATION" -ForegroundColor Cyan
try {
    $installDateRaw = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").InstallDate
    if ($installDateRaw) {
        $installDate = (Get-Date "1970-01-01 00:00:00").AddSeconds($installDateRaw).ToLocalTime()
        Write-Host ("  Install Date : {0}" -f $installDate.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    } else {
        Write-Host "  Install Date : Not found" -ForegroundColor Yellow
    }

    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host ("  OS Version   : {0}" -f $os.Caption) -ForegroundColor White
    Write-Host ("  Build        : {0}" -f $os.BuildNumber) -ForegroundColor White
} catch {
    Write-Host "  Error reading install info" -ForegroundColor Red
}

# ============================================================
# ДИСКИ
# ============================================================
$drives = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -ne 5 }
if ($drives) {
    Write-Host "`nCONNECTED DRIVES" -ForegroundColor Cyan
    foreach ($drive in $drives) {
        Write-Host ("  {0}: {1}" -f $drive.DeviceID, $drive.FileSystem) -ForegroundColor Green
    }
}

# ============================================================
# СЛУЖБЫ
# ============================================================
Write-Host "`nSERVICE STATUS" -ForegroundColor Cyan

$services = @(
    @{Name = "SysMain";    DisplayName = "SysMain"},
    @{Name = "PcaSvc";     DisplayName = "Program Compatibility Assistant"},
    @{Name = "DPS";        DisplayName = "Diagnostic Policy Service"},
    @{Name = "EventLog";   DisplayName = "Windows Event Log"},
    @{Name = "Schedule";   DisplayName = "Task Scheduler"},
    @{Name = "Bam";        DisplayName = "Background Activity Moderator"},
    @{Name = "Dusmsvc";    DisplayName = "Data Usage"},
    @{Name = "Appinfo";    DisplayName = "Application Information"},
    @{Name = "CDPSvc";     DisplayName = "Connected Devices Platform"},
    @{Name = "DcomLaunch"; DisplayName = "DCOM Server Process Launcher"},
    @{Name = "PlugPlay";   DisplayName = "Plug and Play"},
    @{Name = "wsearch";    DisplayName = "Windows Search"},
    @{Name = "icssvc";     DisplayName = "Mobile Hotspot (icssvc)"}
)

foreach ($svc in $services) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($service) {
        $dn = $svc.DisplayName
        if ($dn.Length -gt 40) { $dn = $dn.Substring(0, 37) + "..." }
        if ($service.Status -eq "Running") {
            Write-Host ("  {0,-12} {1,-42}" -f $svc.Name, $dn) -ForegroundColor Green -NoNewline
            if ($svc.Name -eq "Bam") {
                Write-Host " | Enabled" -ForegroundColor Yellow
            } else {
                try {
                    $proc = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" | Select-Object ProcessId
                    if ($proc.ProcessId -gt 0) {
                        $p = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
                        if ($p) { Write-Host (" | {0}" -f $p.StartTime.ToString("HH:mm:ss")) -ForegroundColor Yellow }
                        else    { Write-Host " | N/A" -ForegroundColor Yellow }
                    } else { Write-Host " | N/A" -ForegroundColor Yellow }
                } catch { Write-Host " | N/A" -ForegroundColor Yellow }
            }
        } else {
            Write-Host ("  {0,-12} {1,-42} {2}" -f $svc.Name, $dn, $service.Status) -ForegroundColor Red
        }
    } else {
        Write-Host ("  {0,-12} {1,-42} {2}" -f $svc.Name, "Not Found", "N/A") -ForegroundColor Yellow
    }
}

# ============================================================
# РЕЕСТР
# ============================================================
Write-Host "`nREGISTRY" -ForegroundColor Cyan

$settings = @(
    @{ Name = "CMD";                Path = "HKCU:\Software\Policies\Microsoft\Windows\System";                               Key = "DisableCMD";               Warning = "Disabled"; Safe = "Available" },
    @{ Name = "PowerShell Logging"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging";        Key = "EnableScriptBlockLogging"; Warning = "Disabled"; Safe = "Enabled"   },
    @{ Name = "Activities Cache";   Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                               Key = "EnableActivityFeed";       Warning = "Disabled"; Safe = "Enabled"   },
    @{ Name = "Prefetch Enabled";   Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Key = "EnablePrefetcher"; Warning = "Disabled"; Safe = "Enabled" }
)

foreach ($s in $settings) {
    $status = Get-ItemProperty -Path $s.Path -Name $s.Key -ErrorAction SilentlyContinue
    Write-Host "  " -NoNewline
    if ($status -and $status.$($s.Key) -eq 0) {
        Write-Host "$($s.Name): " -NoNewline -ForegroundColor White
        Write-Host $s.Warning -ForegroundColor Red
    } else {
        Write-Host "$($s.Name): " -NoNewline -ForegroundColor White
        Write-Host $s.Safe -ForegroundColor Green
    }
}

# ============================================================
# EVENT LOGS
# ============================================================
Write-Host "`nEVENT LOGS" -ForegroundColor Cyan

function Check-EventLog {
    param ($logName, $eventID, $message)
    $event = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=$eventID]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event) {
        Write-Host "  $message at: " -NoNewline -ForegroundColor White
        Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
    } else {
        Write-Host "  $message - No records found" -ForegroundColor Green
    }
}

function Check-RecentEventLog {
    param ($logName, $eventIDs, $message)
    $xp = ($eventIDs | ForEach-Object { "EventID=$_" }) -join " or "
    $event = Get-WinEvent -LogName $logName -FilterXPath "*[System[$xp]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event) {
        Write-Host "  $message (ID: $($event.Id)) at: " -NoNewline -ForegroundColor White
        Write-Host $event.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
    } else {
        Write-Host "  $message - No records found" -ForegroundColor Green
    }
}

Check-EventLog      "Application"  3079          "USN Journal cleared"
Check-RecentEventLog "System"      @(104, 1102)  "Event Logs cleared"
Check-EventLog      "System"       1074          "Last PC Shutdown"
Check-EventLog      "System"       6005          "Event Log Service started"

# Device changed
try {
    $ev = Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Configuration" -FilterXPath "*[System[EventID=400]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($ev) {
        Write-Host "  Device config changed at: " -NoNewline -ForegroundColor White
        Write-Host $ev.TimeCreated.ToString("MM/dd HH:mm") -ForegroundColor Yellow
    } else {
        Write-Host "  Device changes - No records found" -ForegroundColor Green
    }
} catch {
    Write-Host "  Device changes - No records found" -ForegroundColor Green
}

# ============================================================
# USN JOURNAL
# ============================================================
Write-Host "`nUSN JOURNAL" -ForegroundColor Cyan
try {
    $usnOutput = fsutil usn queryjournal C: 2>&1
    if ($usnOutput -match "Invalid" -or $usnOutput -match "не удалось") {
        Write-Host "  Status       : DISABLED (журнал отсутствует)" -ForegroundColor Red
    } elseif ($usnOutput -match "Usn Journal ID") {
        Write-Host "  Status       : Enabled" -ForegroundColor Green

        # Последняя ручная очистка — Event ID 3079 в Application log
        $usnClear = Get-WinEvent -LogName "Application" -FilterXPath "*[System[EventID=3079]]" -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($usnClear) {
            Write-Host "  Last cleared : $($usnClear.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Red
        } else {
            Write-Host "  Last cleared : No records found (never cleared manually)" -ForegroundColor Green
        }

        # First USN — косвенный признак сброса журнала (большое значение = не сбрасывался)
        $firstUsn = $usnOutput | Select-String "First Usn"
        if ($firstUsn) {
            $usnVal = $firstUsn.Line.Trim()
            Write-Host "  $usnVal" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Status       : Unknown" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Error reading USN Journal" -ForegroundColor Red
}

# ============================================================
# PREFETCH
# ============================================================
$prefetchPath = "$env:SystemRoot\Prefetch"
if (Test-Path $prefetchPath) {
    Write-Host "`nPREFETCH INTEGRITY" -ForegroundColor Cyan

    $files = Get-ChildItem -Path $prefetchPath -Filter *.pf -Force -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host "  No prefetch files found" -ForegroundColor Yellow
    } else {
        $totalFiles = $files.Count
        $hashTable  = @{}
        $suspiciousFiles = @{}
        $hiddenFiles = @(); $readOnlyFiles = @(); $hiddenAndRO = @()

        foreach ($file in $files) {
            try {
                $isH  = $file.Attributes -band [System.IO.FileAttributes]::Hidden
                $isRO = $file.Attributes -band [System.IO.FileAttributes]::ReadOnly

                if ($isH -and $isRO) { $hiddenAndRO += $file; $suspiciousFiles[$file.Name] = "Hidden and Read-only" }
                elseif ($isH)        { $hiddenFiles  += $file; $suspiciousFiles[$file.Name] = "Hidden file" }
                elseif ($isRO)       { $readOnlyFiles += $file; $suspiciousFiles[$file.Name] = "Read-only file" }

                $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue
                if ($hash) {
                    if ($hashTable.ContainsKey($hash.Hash)) { $hashTable[$hash.Hash].Add($file.Name) }
                    else { $hashTable[$hash.Hash] = [System.Collections.Generic.List[string]]::new(); $hashTable[$hash.Hash].Add($file.Name) }
                }
            } catch { $suspiciousFiles[$file.Name] = "Error: $($_.Exception.Message)" }
        }

        if ($hiddenAndRO.Count   -gt 0) { Write-Host "  Hidden & Read-only: $($hiddenAndRO.Count)"   -ForegroundColor Yellow; $hiddenAndRO   | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor White } }
        if ($hiddenFiles.Count   -gt 0) { Write-Host "  Hidden Files: $($hiddenFiles.Count)"          -ForegroundColor Yellow; $hiddenFiles   | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor White } }
        else                            { Write-Host "  Hidden Files: None"    -ForegroundColor Green }
        if ($readOnlyFiles.Count -gt 0) { Write-Host "  Read-Only Files: $($readOnlyFiles.Count)"     -ForegroundColor Yellow; $readOnlyFiles | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor White } }
        else                            { Write-Host "  Read-Only Files: None" -ForegroundColor Green }

        $dupes = $hashTable.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($dupes) {
            Write-Host "  Duplicates: $($dupes | Measure-Object).Count set(s)" -ForegroundColor Yellow
            foreach ($e in $dupes) {
                $e.Value | ForEach-Object { if (-not $suspiciousFiles.ContainsKey($_)) { $suspiciousFiles[$_] = "Duplicate" } }
                Write-Host "    $($e.Value -join ', ')" -ForegroundColor White
            }
        } else { Write-Host "  Duplicates: None" -ForegroundColor Green }

        if ($suspiciousFiles.Count -gt 0) {
            Write-Host "`n  SUSPICIOUS: $($suspiciousFiles.Count)/$totalFiles" -ForegroundColor Yellow
            foreach ($e in $suspiciousFiles.GetEnumerator() | Sort-Object Key) {
                Write-Host "    $($e.Key) : $($e.Value)" -ForegroundColor White
            }
        } else {
            Write-Host "`n  Prefetch integrity: Clean ($totalFiles files)" -ForegroundColor Green
        }
    }
} else {
    Write-Host "`nPREFETCH folder not found" -ForegroundColor Red
}

# ============================================================
# КОРЗИНА
# ============================================================
Write-Host "`nRECYCLE BIN" -ForegroundColor Cyan
try {
    $rbPath = "$env:SystemDrive\`$Recycle.Bin"
    if (Test-Path $rbPath) {
        $rbFolder    = Get-Item -LiteralPath $rbPath -Force
        $userFolders = Get-ChildItem -LiteralPath $rbPath -Directory -Force -ErrorAction SilentlyContinue
        $allItems    = @()
        $latestMod   = $rbFolder.LastWriteTime

        foreach ($uf in $userFolders) {
            if ($uf.LastWriteTime -gt $latestMod) { $latestMod = $uf.LastWriteTime }
            $uItems = Get-ChildItem -LiteralPath $uf.FullName -File -Force -ErrorAction SilentlyContinue
            if ($uItems) {
                $allItems += $uItems
                $lf = $uItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($lf -and $lf.LastWriteTime -gt $latestMod) { $latestMod = $lf.LastWriteTime }
            }
        }

        Write-Host "  Last Modified: $($latestMod.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
        if ($allItems.Count -gt 0) {
            Write-Host "  Total Items: $($allItems.Count)" -ForegroundColor Yellow
            $latest = $allItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Write-Host "  Latest Item: $($latest.Name)" -ForegroundColor Gray
        } else {
            Write-Host "  Status: Empty" -ForegroundColor Green
        }
    } else {
        Write-Host "  Recycle Bin not found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================
# ИСТОРИЯ POWERSHELL
# ============================================================
Write-Host "`nPOWERSHELL HISTORY" -ForegroundColor Cyan
$histPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
if (Test-Path $histPath) {
    $hf = Get-Item -Path $histPath -Force
    Write-Host "  Last Modified : $($hf.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
    Write-Host "  File Size     : $([math]::Round($hf.Length/1024, 2)) KB" -ForegroundColor White
    $attrs = $hf.Attributes
    if ($attrs -ne "Archive") { Write-Host "  Attributes    : $attrs" -ForegroundColor Yellow }
    else                      { Write-Host "  Attributes    : Normal" -ForegroundColor Green }
} else {
    Write-Host "  History file not found (disabled or never used)" -ForegroundColor Yellow
}

# ============================================================
# HOTSPOT / FAKER DETECTION
# ============================================================
Write-Host "`nHOTSPOT / FAKER DETECTION" -ForegroundColor Cyan

$suspAct       = @()
$fakerDetected = $false
$fakerIndicators = @()

# Профили WiFi
$networkProfiles = @()
try {
    $profileOutput = netsh wlan show profiles
    $profileNames  = $profileOutput | Select-String "All User Profile\s+:\s+(.+)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    foreach ($pn in $profileNames) {
        if ([string]::IsNullOrWhiteSpace($pn)) { continue }
        $isHs = $pn -match "Android|iPhone|iPad|Galaxy|Pixel|OnePlus|Xiaomi|DIRECT-|SM-|GT-"
        $networkProfiles += [PSCustomObject]@{ SSID = $pn; IsHotspot = $isHs }
    }
    $hotspotProfiles = $networkProfiles | Where-Object { $_.IsHotspot }
    if ($hotspotProfiles.Count -gt 0) {
        Write-Host "  Hotspot profiles found: $($hotspotProfiles.Count)" -ForegroundColor Yellow
        foreach ($hp in $hotspotProfiles) { Write-Host "    - $($hp.SSID)" -ForegroundColor Yellow }
    } else {
        Write-Host "  WiFi profiles: no mobile hotspots detected" -ForegroundColor Green
    }
} catch {}

# Текущее подключение
try {
    $ifaceOut   = netsh wlan show interfaces
    $ssidM      = $ifaceOut | Select-String "^\s+SSID\s+:\s+(.+)$"
    $stateM     = $ifaceOut | Select-String "^\s+State\s+:\s+(.+)$"
    $bssidM     = $ifaceOut | Select-String "^\s+BSSID\s+:\s+(.+)$"
    $channelM   = $ifaceOut | Select-String "^\s+Channel\s+:\s+(.+)$"
    $signalM    = $ifaceOut | Select-String "^\s+Signal\s+:\s+(.+)$"

    if ($ssidM -and $stateM) {
        $curSSID  = $ssidM.Matches.Groups[1].Value.Trim()
        $curState = $stateM.Matches.Groups[1].Value.Trim()
        $bssid    = if ($bssidM)   { $bssidM.Matches.Groups[1].Value.Trim() }   else { "N/A" }
        $channel  = if ($channelM) { $channelM.Matches.Groups[1].Value.Trim() } else { "N/A" }
        $signal   = if ($signalM)  { $signalM.Matches.Groups[1].Value.Trim() }  else { "N/A" }

        if ($curState -eq "connected") {
            $isHs = $false
            $hsIndicators = @()

            $hotspotPatterns = @('Android','iPhone','iPad','Galaxy','Pixel','OnePlus','Xiaomi','Huawei','Oppo','Vivo','Realme','Nokia','DIRECT-','SM-[A-Z0-9]','GT-[A-Z0-9]','Redmi',"'s iPhone","'s Galaxy","'s Pixel")
            foreach ($pat in $hotspotPatterns) {
                if ($curSSID -match $pat) { $isHs = $true; $hsIndicators += "SSID matches: $pat"; break }
            }

            if ($bssid -ne "N/A") {
                $secondChar = $bssid.Substring(1,1)
                if ($secondChar -match "[26AEae]") { $isHs = $true; $hsIndicators += "BSSID locally administered (hotspot typical)" }
            }

            try {
                $gw = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.DefaultIPGateway }).DefaultIPGateway | Select-Object -First 1
                if ($gw) {
                    if ($gw -like "192.168.137.*") { $isHs = $true; $fakerDetected = $true; $fakerIndicators += "Windows PC Hotspot gateway (192.168.137.x)"; $hsIndicators += "Gateway = Windows Mobile Hotspot — FAKER INDICATOR" }
                    elseif ($gw -eq "192.168.43.1") { $isHs = $true; $hsIndicators += "Gateway = Android hotspot (192.168.43.1)" }
                    elseif ($gw -eq "192.168.49.1") { $isHs = $true; $hsIndicators += "Gateway = Android hotspot (192.168.49.1)" }
                }
            } catch {}

            Write-Host "  Connected to: $curSSID" -ForegroundColor $(if ($isHs) { "Red" } else { "Green" })
            Write-Host "    BSSID: $bssid | Channel: $channel | Signal: $signal" -ForegroundColor Gray
            if ($isHs) {
                Write-Host "  WARNING: HOTSPOT DETECTED!" -ForegroundColor Red
                foreach ($ind in $hsIndicators) { Write-Host "    - $ind" -ForegroundColor Yellow }
                $suspAct += "Connected to hotspot: $curSSID"
            }
        }
    }
} catch {}

# Hosted network
try {
    $hnOut     = netsh wlan show hostednetwork
    $hnStatus  = $hnOut | Select-String "Status\s+:\s+(.+)"
    if ($hnStatus -and $hnStatus.Matches.Groups[1].Value.Trim() -eq "Started") {
        $hnSSIDMatch = $hnOut | Select-String 'SSID name\s+:\s+"(.+)"'
    $hnSSID = if ($hnSSIDMatch) { $hnSSIDMatch.Matches.Groups[1].Value } else { "Unknown" }
        Write-Host "  WARNING: Hosted Network ACTIVE! SSID: $hnSSID" -ForegroundColor Red
        $suspAct += "Hosted network active: $hnSSID"
    } else {
        Write-Host "  Hosted Network: Inactive" -ForegroundColor Green
    }
} catch {}

# icssvc (Mobile Hotspot service)
$icssvc = Get-Service -Name "icssvc" -ErrorAction SilentlyContinue
if ($icssvc) {
    if ($icssvc.Status -eq "Running") {
        Write-Host "  Mobile Hotspot service (icssvc): RUNNING" -ForegroundColor Red
        $suspAct += "icssvc (Mobile Hotspot) is running"
    } else {
        Write-Host "  Mobile Hotspot service (icssvc): Stopped" -ForegroundColor Green
    }
}

# Virtual adapters
try {
    $vAdapters = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true -and $_.Description -match "Virtual|Hosted|Wi-Fi Direct|TAP" }
    if ($vAdapters) {
        foreach ($va in $vAdapters) { Write-Host "  Virtual adapter: $($va.Description)" -ForegroundColor Yellow }
        $suspAct += "$($vAdapters.Count) virtual adapter(s) found"
    } else {
        Write-Host "  Virtual adapters: None" -ForegroundColor Green
    }
} catch {}

# ============================================================
# SFC SCANNOW
# ============================================================
Write-Host "`nSFC SCANNOW" -ForegroundColor Cyan
Write-Host "  Running... (may take a few minutes)" -ForegroundColor Yellow
$sfcResult = sfc /scannow 2>&1
# Показываем только итоговую строку — без прогресса
$sfcSummary = $sfcResult | Where-Object { $_ -match "protection|found|repair|did not find|resource" } | Select-Object -Last 1
if ($sfcSummary) {
    $color = if ($sfcSummary -match "did not find") { "Green" } else { "Yellow" }
    Write-Host "  Result: $($sfcSummary.ToString().Trim())" -ForegroundColor $color
} else {
    Write-Host "  Result: completed (check CBS.log for details)" -ForegroundColor White
}

# ============================================================
# JAVA PORTS (Minecraft и другие java-процессы)
# ============================================================
Write-Host "`nJAVA PROCESSES & PORTS" -ForegroundColor Cyan

$javaProcs = Get-Process -Name "java" -ErrorAction SilentlyContinue
if (-not $javaProcs) {
    Write-Host "  No java.exe processes running" -ForegroundColor Green
} else {
    Write-Host "  Found $($javaProcs.Count) java process(es):" -ForegroundColor Yellow

    # Собираем netstat один раз
    $netstatLines = netstat -ano | Select-String "LISTENING|ESTABLISHED"

    foreach ($jp in $javaProcs) {
        Write-Host "`n  PID $($jp.Id) — $($jp.ProcessName)" -ForegroundColor White
        Write-Host "    Started : $($jp.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray

        # Командная строка процесса (показывает jar/аргументы)
        try {
            $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId=$($jp.Id)").CommandLine
            if ($cmdLine) {
                $short = if ($cmdLine.Length -gt 120) { $cmdLine.Substring(0, 117) + "..." } else { $cmdLine }
                Write-Host "    CMD     : $short" -ForegroundColor Gray
            }
        } catch {}

        # Порты этого PID
        $pidPorts = $netstatLines | Where-Object { $_ -match "\s+$($jp.Id)\s*$" }
        if ($pidPorts) {
            Write-Host "    Ports   :" -ForegroundColor Cyan
            foreach ($line in $pidPorts) {
                $line = $line.Line.Trim()
                # Подсветить Minecraft-порты
                $color = if ($line -match ":25\d{3}") { "Red" } else { "White" }
                Write-Host "      $line" -ForegroundColor $color
            }
        } else {
            Write-Host "    Ports   : none found" -ForegroundColor Gray
        }
    }
}

# ============================================================
# ИТОГ
# ============================================================
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Suspicious activities : $($suspAct.Count)" -ForegroundColor $(if ($suspAct.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  Faker detected        : $(if ($fakerDetected) { 'YES' } else { 'No' })" -ForegroundColor $(if ($fakerDetected) { "Red" } else { "Green" })
Write-Host "  Hotspot profiles      : $(($networkProfiles | Where-Object { $_.IsHotspot }).Count)" -ForegroundColor White

if ($suspAct.Count -gt 0) {
    Write-Host "`n  Warnings:" -ForegroundColor Red
    foreach ($a in $suspAct) { Write-Host "    - $a" -ForegroundColor Yellow }
}

if ($fakerIndicators.Count -gt 0) {
    Write-Host "`n  Faker indicators:" -ForegroundColor Red
    foreach ($fi in $fakerIndicators) { Write-Host "    - $fi" -ForegroundColor Yellow }
}

Write-Host "`nCheck complete. Hit up @praiselily if u run into any issues." -ForegroundColor Cyan
Write-Host ""
