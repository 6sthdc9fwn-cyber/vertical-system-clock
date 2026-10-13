# Vertical System Clock - helper
# Raccoglie le informazioni di sistema e le offre allo sfondo tramite un piccolo server HTTP
# raggiungibile SOLO da questo PC (http://127.0.0.1:47811/stats).
# Collects system information and serves it to the wallpaper through a tiny HTTP server
# reachable ONLY from this PC (http://127.0.0.1:47811/stats).
#
# Uso / Usage:
#   powershell -ExecutionPolicy Bypass -File sysinfo.ps1         (server continuo / keeps running)
#   powershell -ExecutionPolicy Bypass -File sysinfo.ps1 -Once   (stampa il JSON e esce / prints JSON and exits)
# Temperature, ventole e frequenze arrivano da LibreHardwareMonitor (server web su localhost:8085).
param([switch]$Once, [int]$Interval = 2, [string]$PingHost = '1.1.1.1', [int]$LhmPort = 8085, [int]$Port = 47811)

$ErrorActionPreference = 'SilentlyContinue'

# Registro errori accanto allo script (max ~200 KB): un errore viene annotato e l'helper prosegue
$logFile = Join-Path $PSScriptRoot 'helper.log'
function Write-Log([string]$msg) {
    try {
        if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 200KB) { Remove-Item $logFile -Force }
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    } catch {}
}
trap { Write-Log "errore: $_"; continue }

# Una sola istanza alla volta (un mutex "abbandonato" da un'istanza chiusa male vale come acquisito)
$mutex = New-Object System.Threading.Mutex($false, 'Global\VerticalSysClockMonitor')
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (-not $Once -and -not $owned) { exit }

$enc = New-Object System.Text.UTF8Encoding($false)

# Server in ascolto solo sull'indirizzo di loopback: nessun altro computer può collegarsi
$listener = $null
if (-not $Once) {
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
    } catch {
        # porta occupata o rete non ancora pronta: esce, l'avviatore riprova tra 30 secondi
        Write-Log "impossibile aprire la porta $Port : $_"
        exit 1
    }
    Write-Log "avviato, in ascolto su 127.0.0.1:$Port"
}

function Send-Response($client, [string]$body) {
    try {
        $stream = $client.GetStream()
        $stream.ReadTimeout = 500
        $buf = New-Object byte[] 4096
        $req = ''
        try { $n = $stream.Read($buf, 0, $buf.Length); $req = [Text.Encoding]::ASCII.GetString($buf, 0, $n) } catch {}
        $cors = "Access-Control-Allow-Origin: *`r`nAccess-Control-Allow-Private-Network: true`r`nAccess-Control-Allow-Methods: GET, OPTIONS`r`nAccess-Control-Allow-Headers: *`r`n"
        if ($req.StartsWith('OPTIONS')) {
            $head = "HTTP/1.1 204 No Content`r`n$cors" + "Content-Length: 0`r`nConnection: close`r`n`r`n"
            $bytes = [Text.Encoding]::ASCII.GetBytes($head)
        } else {
            $payload = $enc.GetBytes($body)
            $head = "HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nCache-Control: no-store`r`n$cors" +
                    "Content-Length: $($payload.Length)`r`nConnection: close`r`n`r`n"
            $bytes = [Text.Encoding]::ASCII.GetBytes($head) + $payload
        }
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    } catch {} finally { $client.Close() }
}

# ---------- Dati statici (letti una volta sola) ----------
$osInfo  = Get-CimInstance Win32_OperatingSystem
$osName  = ($osInfo.Caption -replace '^Microsoft\s+', '').Trim()
$cpuName = ((Get-CimInstance Win32_Processor | Select-Object -First 1).Name -replace '\s+', ' ').Trim()
$gpuName = (Get-CimInstance Win32_VideoController |
            Where-Object { $_.Name -notmatch 'Basic|Virtual|Remote|Parsec|Meta|Mirror' } |
            Select-Object -First 1).Name
$cores   = [int](Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum

# Nome per il saluto: il nome proprio dell'account Windows, altrimenti il nome utente
$fullName  = (Get-LocalUser -Name $env:USERNAME).FullName
$firstName = if ($fullName) { ($fullName.Trim() -split '\s+')[0] } else { $env:USERNAME }

# Lettera di unità -> modello del disco fisico (per abbinare le temperature dei dischi)
$driveModel = @{}
foreach ($dd in Get-CimInstance Win32_DiskDrive) {
    foreach ($part in Get-CimAssociatedInstance -InputObject $dd -ResultClassName Win32_DiskPartition) {
        foreach ($ld in Get-CimAssociatedInstance -InputObject $part -ResultClassName Win32_LogicalDisk) {
            $driveModel[$ld.DeviceID] = "$($dd.Model)".Trim()
        }
    }
}

$pinger = New-Object System.Net.NetworkInformation.Ping
$prevRx = $null; $prevTx = $null; $prevT = $null
$prevCpu = @{}

# "59,0 °C" -> 59.0
function Num($s) {
    if ("$s" -match '-?\d+(?:[.,]\d+)?') { return [double]($Matches[0] -replace ',', '.') }
    return $null
}

# Legge LibreHardwareMonitor e restituisce i valori utili (o $null se non è attivo)
function Test-Port([int]$p) {
    # controllo rapido: se LibreHardwareMonitor non è aperto non aspettiamo il timeout HTTP
    $c = New-Object System.Net.Sockets.TcpClient
    try { return $c.ConnectAsync('127.0.0.1', $p).Wait(150) -and $c.Connected } catch { return $false } finally { $c.Close() }
}

function Get-Lhm {
    if (-not (Test-Port $LhmPort)) { return $null }
    try { $root = Invoke-RestMethod "http://127.0.0.1:$LhmPort/data.json" -TimeoutSec 1 } catch { return $null }
    if (-not $root) { return $null }

    $sensors = New-Object System.Collections.ArrayList
    $hwNames = @{}
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    while ($stack.Count) {
        $n = $stack.Pop()
        if ($n.HardwareId) { $hwNames[$n.HardwareId] = "$($n.Text)".Trim() }
        if ($n.SensorId) { [void]$sensors.Add($n) }
        foreach ($c in $n.Children) { $stack.Push($c) }
    }
    $find = { param($idRx, $type, $textRx)
        $sensors | Where-Object { $_.SensorId -match $idRx -and $_.Type -eq $type -and $_.Text -match $textRx } }
    $val = { param($idRx, $type, $textRx)
        $s = & $find $idRx $type $textRx | Select-Object -First 1
        if ($s) { Num $s.Value } else { $null } }

    $cpuRx = '^/(intelcpu|amdcpu)/'
    $gpuRx = '^/gpu-'

    $cpuTemp = & $val $cpuRx 'Temperature' '^(CPU Package|Core \(Tctl/Tdie\)|Package)$'
    if ($null -eq $cpuTemp) { $cpuTemp = & $val $cpuRx 'Temperature' '^Core Max$' }

    $coreClocks = & $find $cpuRx 'Clock' '^(CPU )?Core #\d+$' | ForEach-Object { Num $_.Value }
    $cpuClock = if ($coreClocks) { ($coreClocks | Measure-Object -Average).Average } else { $null }

    # Carico e temperatura per ogni core fisico (media dei thread)
    $coreLoad = @{}; $coreTemp = @{}
    foreach ($s in & $find $cpuRx 'Load' '^CPU Core #\d+( Thread #\d+)?$') {
        $k = [int]([regex]::Match($s.Text, '#(\d+)').Groups[1].Value)
        if (-not $coreLoad[$k]) { $coreLoad[$k] = New-Object System.Collections.ArrayList }
        [void]$coreLoad[$k].Add((Num $s.Value))
    }
    foreach ($s in & $find $cpuRx 'Temperature' '^CPU Core #\d+$') {
        $coreTemp[[int]([regex]::Match($s.Text, '#(\d+)').Groups[1].Value)] = Num $s.Value
    }
    $coreList = @($coreLoad.Keys | Sort-Object | ForEach-Object {
        @{ n = $_; l = [math]::Round(($coreLoad[$_] | Measure-Object -Average).Average, 1); t = $coreTemp[$_] }
    })

    $fans = @($sensors | Where-Object { $_.Type -eq 'Fan' } | ForEach-Object {
        $isGpu = $_.SensorId -match $gpuRx
        # numero della ventola: il nome ("Ventola 2" / "Fan 2") lo compone lo sfondo nella lingua scelta
        $name = if ($isGpu) { 'GPU' } elseif ($_.Text -match '^Fan #(\d+)$') { $Matches[1] } else { $_.Text }
        @{ n = $name; rpm = Num $_.Value; gpu = $isGpu }
    })

    $dimms = & $find '^/memory/dimm/' 'Temperature' '^DIMM #\d+$' | ForEach-Object { Num $_.Value }

    # Temperatura per ogni disco fisico, indicizzata per nome del modello
    $diskTemps = @{}
    # prima "Composite Temperature"/"Temperature", mai le soglie di allarme
    $storTemps = $sensors | Where-Object {
        $_.Type -eq 'Temperature' -and $_.SensorId -match '^/(nvme|ssd|hdd)/' -and $_.Text -notmatch 'Warning|Critical|Limit|Resolution'
    } | Sort-Object { if ($_.Text -match '^(Composite )?Temperature$') { 0 } else { 1 } }
    foreach ($s in $storTemps) {
        $hwId = ($s.SensorId -split '/')[0..2] -join '/'
        $name = $hwNames[$hwId]
        if ($name -and -not $diskTemps.ContainsKey($name)) { $diskTemps[$name] = Num $s.Value }
    }

    return @{
        cpuTemp  = $cpuTemp
        cpuClock = $cpuClock
        cpuPower = & $val $cpuRx 'Power' '^(CPU Package|Package)$'
        gpuTemp  = & $val $gpuRx 'Temperature' '^GPU Core$'
        gpuHot   = & $val $gpuRx 'Temperature' '^GPU Hot Spot$'
        gpuClock = & $val $gpuRx 'Clock' '^GPU Core$'
        gpuMemClock = & $val $gpuRx 'Clock' '^GPU Memory$'
        gpuLoad  = & $val $gpuRx 'Load' '^GPU Core$'
        gpuPower = & $val $gpuRx 'Power' '^(GPU Package|GPU Power|GPU Board Power)$'
        vramUsed = & $val $gpuRx 'SmallData' '^GPU Memory Used$'
        vramTot  = & $val $gpuRx 'SmallData' '^GPU Memory Total$'
        ramTemp  = if ($dimms) { [math]::Round(($dimms | Measure-Object -Average).Average, 1) } else { $null }
        cores    = $coreList
        fans     = $fans
        diskTemps = $diskTemps
    }
}

while ($true) {
    $now = Get-Date

    # CPU (classi WMI non localizzate, funzionano anche su Windows in italiano)
    $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime

    # RAM + uptime
    $os = Get-CimInstance Win32_OperatingSystem
    $ramTot  = [double]$os.TotalVisibleMemorySize * 1KB
    $ramFree = [double]$os.FreePhysicalMemory * 1KB
    $uptime  = [int]($now - $os.LastBootUpTime).TotalSeconds

    # Sensori hardware
    $lhm = Get-Lhm

    # GPU: da LibreHardwareMonitor se c'è, altrimenti somma dei motori 3D
    $gpu = $null
    if ($lhm -and $null -ne $lhm.gpuLoad) { $gpu = $lhm.gpuLoad }
    else {
        $eng = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -Filter "Name LIKE '%engtype_3D%'"
        if ($eng) { $gpu = [math]::Min(100, ($eng | Measure-Object UtilizationPercentage -Sum).Sum) }
    }

    # Dischi locali con velocità di lettura/scrittura e temperatura
    $io = @{}
    foreach ($p in Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk) { $io[$p.Name] = $p }
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        $temp = $null
        $model = $driveModel[$_.DeviceID]
        if ($lhm -and $model) {
            foreach ($k in $lhm.diskTemps.Keys) { if ($k -eq $model -or $k -like "*$model*" -or $model -like "*$k*") { $temp = $lhm.diskTemps[$k]; break } }
        }
        @{
            n = $_.DeviceID; l = $_.VolumeName; t = [double]$_.Size; f = [double]$_.FreeSpace
            r = [double]$io[$_.DeviceID].DiskReadBytesPersec
            w = [double]$io[$_.DeviceID].DiskWriteBytesPersec
            temp = $temp
        }
    })
    if ($lhm) { $lhm.Remove('diskTemps') }

    # Rete (solo schede fisiche attive)
    $st = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Get-NetAdapterStatistics
    $rx = [double]($st | Measure-Object ReceivedBytes -Sum).Sum
    $tx = [double]($st | Measure-Object SentBytes -Sum).Sum
    $down = 0; $up = 0
    $dt = 0
    if ($prevT) {
        $dt = ($now - $prevT).TotalSeconds
        if ($dt -gt 0) {
            $down = [math]::Max(0, ($rx - $prevRx) / $dt)
            $up   = [math]::Max(0, ($tx - $prevTx) / $dt)
        }
    }
    $prevRx = $rx; $prevTx = $tx; $prevT = $now

    # Ping
    $ping = $null
    try { $r = $pinger.Send($PingHost, 700); if ($r.Status -eq 'Success') { $ping = [int]$r.RoundtripTime } } catch {}

    # Programmi che usano più CPU e RAM (raggruppati per nome, come in Gestione attività)
    $byName = @{}
    $curCpu = @{}
    foreach ($p in Get-Process) {
        if ($p.Id -eq 0) { continue }
        $name = $p.ProcessName
        if (-not $byName[$name]) { $byName[$name] = @{ n = $name; c = 0.0; m = 0.0 } }
        $byName[$name].m += [double]$p.WorkingSet64
        $t = $p.TotalProcessorTime
        if ($t) {
            $curCpu[$p.Id] = $t.TotalSeconds
            if ($dt -gt 0 -and $prevCpu.ContainsKey($p.Id)) {
                $byName[$name].c += [math]::Max(0, ($t.TotalSeconds - $prevCpu[$p.Id]) / ($dt * $cores) * 100)
            }
        }
    }
    $prevCpu = $curCpu
    $all = $byName.Values
    $topCpu = @($all | Sort-Object { $_.c } -Descending | Select-Object -First 8 | ForEach-Object { @{ n = $_.n; v = [math]::Round($_.c, 1) } })
    $topRam = @($all | Sort-Object { $_.m } -Descending | Select-Object -First 8 | ForEach-Object { @{ n = $_.n; v = $_.m } })

    $data = @{
        ts      = [long]([DateTimeOffset]$now).ToUnixTimeMilliseconds()
        host    = $env:COMPUTERNAME
        user    = $env:USERNAME
        name    = $firstName
        os      = $osName
        cpuName = $cpuName
        gpuName = $gpuName
        cores   = $cores
        cpu     = $cpu
        gpu     = $gpu
        ramTot  = $ramTot
        ramUsed = $ramTot - $ramFree
        uptime  = $uptime
        disks   = $disks
        down    = $down
        up      = $up
        ping    = $ping
        pingHost = $PingHost
        topCpu  = $topCpu
        topRam  = $topRam
        hw      = $lhm
    }

    $json = $data | ConvertTo-Json -Compress -Depth 6

    # con -Once fa due giri, perché velocità e CPU dei programmi si calcolano tra due letture
    if ($Once) {
        if (++$runs -ge 2) { $json; break }
        Start-Sleep -Seconds $Interval
        continue
    }

    # fino alla prossima lettura risponde alle richieste dello sfondo con i dati più recenti
    $until = (Get-Date).AddSeconds($Interval)
    while ((Get-Date) -lt $until) {
        while ($listener.Pending()) { Send-Response $listener.AcceptTcpClient() $json }
        Start-Sleep -Milliseconds 40
    }
}
