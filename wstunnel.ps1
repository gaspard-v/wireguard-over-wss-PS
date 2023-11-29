#Requires -RunAsAdministrator

Param(
    [Parameter(Mandatory)]
    [string]
    $FUNC
)

$ErrorActionPreference = "Stop"


$WG = $env:WIREGUARD_TUNNEL_NAME

$DEFAULT_HOSTS_FILE = "${Env:SystemRoot}\system32\drivers\etc\hosts"
$CFG = "$PSScriptRoot\${WG}.wstunnel.ps1"
$APPDATA = "${env:LOCALAPPDATA}\wstunnel"
$PID_FILE = "${APPDATA}\${WG}.pid"
$WSTUNNEL_PATH = "wstunnel.exe"

if ($env:WSTUNNEL_CONFIG_DIR) {
    $CFG = "$env:WSTUNNEL_CONFIG_DIR\${WG}.wstunnel.ps1"
}

if (-not (Test-Path -PathType Leaf -Path $CFG)) {
    throw "[#] missing config file: `"${CFG}`""
}

. "$CFG"

if (-not ($UPDATE_HOSTS)) {
    $UPDATE_HOSTS = $DEFAULT_HOSTS_FILE
}

if ($WSTUNNEL_EXEC_PATH) {
    $WSTUNNEL_PATH = $WSTUNNEL_EXEC_PATH
}

if (-not $LOGS_DIR) {
    $LOGS_DIR = $PSScriptRoot
}

if (-not $DISABLE_LOGS) {
    Start-Transcript -Append -Path "$LOGS_DIR\${WG}_${FUNC}.log"
}



function add_host_entry([string] $current_host, [string] $current_ip) {
    Write-Output "[#] Add new entry ${current_host} => <${current_ip}>"
    "`n${current_ip}`t${current_host}" | Out-File -Append -Encoding utf8 -NoNewline -FilePath $UPDATE_HOSTS
}

function update_host_entry([string] $current_host, [string] $current_ip) {
    $file_content = Get-Content "$UPDATE_HOSTS"
    [string] $content = ""
    foreach ($line in $file_content) {
        if ($line -match $current_host) {
            Write-Output "[#] Updating ${current_host} -> ${current_ip}"
            $content += "${current_ip}`t${current_host}`n"
        }
        else {
            $content += "${line}`n"
        }
    }
    $content.Substring(0, $content.Length - 1) | Out-File -NoNewline -Encoding utf8 "$UPDATE_HOSTS"
}

function delete_host_entry([string] $current_host, [string] $current_ip) {
    $file_content = Get-Content "$UPDATE_HOSTS"
    [string] $content = ""
    Write-Output "[#] delete entry ${current_host} -> ${current_ip}"
    foreach ($line in $file_content) {
        if ($line -notmatch $current_host) {
            $content += "${line}`n"
        }
    }
    $content.Substring(0, $content.Length - 1) | Out-File -NoNewline -Encoding utf8 "$UPDATE_HOSTS"
}

function maybe_update_host([string] $current_host, [string] $current_ip) {
    if ([ipaddress]::TryParse("$current_host", [ref][ipaddress]::Loopback)) {
        # the $current_host is a loopback ip address
        Write-Output "[#] ${current_host} is an IP address"
        return
    }
    $file_content = Get-Content "$UPDATE_HOSTS"
    if ($file_content -match $current_host) {
        update_host_entry $current_host $current_ip
    }
    else {
        add_host_entry $current_host $current_ip
    }
}

function bg([string] $prog, [string[]] $params) {
    Write-Output "[#] Launch in background `"${prog}`" with parameters ${params}" 
    return Start-Process -NoNewWindow -FilePath $prog -ArgumentList $params -PassThru
}

function launch_wstunnel() {
    $rport = $REMOTE_PORT
    if ($LOCAL_PORT) {
        $lport = $LOCAL_PORT
    }
    else {
        $lport = $rport
    }
    if ($WSS_PORT) {
        $wssport = $WSS_PORT
    }
    else {
        $wssport = 443
    }
    $param = @("client",
        "wss://${REMOTE_HOST}:$wssport",
        "--local-to-remote",
        "udp://127.0.0.1:${lport}:127.0.0.1:${rport}?timeout_sec=0")
    if ($WS_PREFIX) {
        $param += "--http-upgrade-path-prefix"
        $param += "${WS_PREFIX}"
    }

    if ($HTTP_PROXY) {
        $param += "--http-proxy"
        $param += "${HTTP_PROXY}"
    }
    $wspid = (bg -prog $WSTUNNEL_PATH -params $param).id
    New-Item -Path "${APPDATA}" -Force -ItemType "directory" | Out-Null
    "${wspid} ${env:REMOTE_IP4} ${env:GW4} ${REMOTE_HOST}" | Out-File -NoNewline -FilePath "${PID_FILE}"
}

function pre_up() {
    if ([ipaddress]::TryParse("$current_host", [ref][ipaddress]::Loopback)) {
        Write-Warning -Message "You should specifie a domain name instead of a direct IP address"
        $remote_ip4 = [IPAddress] $REMOTE_HOST
    }
    else {
        try {
            $remote_ip = [System.Net.Dns]::GetHostAddresses($REMOTE_HOST)
            foreach ($ip in $remote_ip) {
                if ($ip.AddressFamily -eq "InterNetwork") {
                    $remote_ip4 = $ip.IPAddressToString
                    Write-Output "[#] Found IPv4 ${remote_ip4} for host ${REMOTE_HOST}"
                }
                elseif ($ip.AddressFamily -eq "InterNetworkV6") {
                    $remote_ip6 = $ip.IPAddressToString
                    Write-Output "[#] Found IPv6 ${remote_ip6} for host ${REMOTE_HOST}"
                }
            }
        }
        catch {
            Write-Warning "Unable to resolve host `"${$REMOTE_HOST}`""
            if (-not $OVERRIDE_IPv4 -and -not $OVERRIDE_IPv6) {
                Write-Error "Please set OVERRIDE_IPv4 or/and OVERRIDE_IPv6 !"
                exit(1)
            }
            if ($OVERRIDE_IPv4) { $remote_ip4 = $OVERRIDE_IPv4 }
            if ($OVERRIDE_IPv6) { $remote_ip6 = $OVERRIDE_IPv6 }

        }
    }
    maybe_update_host -current_host $REMOTE_HOST -current_ip $remote_ip4
    # Find out the current route to $remote_ip and make it explicit
    [string] $gw4 = (Find-NetRoute -RemoteIPAddress $remote_ip4).NextHop
    $gw4 = $gw4.Trim()
    route add ${remote_ip4}/32 ${gw4} | Out-Null
    # Start wstunnel
    Start-Job -ScriptBlock {
        param($remote_ip4, $gw4)
        $env:REMOTE_IP4 = $remote_ip4
        $env:GW4 = $gw4
        Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList @("-File", $input, "launch_wstunnel")
    } -InputObject $PSCommandPath -ArgumentList $remote_ip4, $gw4
}

function post_up() {
    $interface = (Get-NetAdapter -Name "${WG}*").ifIndex
    try {
        $ipv4 = (Get-NetIPAddress -InterfaceIndex $interface -AddressFamily IPv4).IPAddress
        route add 0.0.0.0/0 ${ipv4} METRIC 1 IF ${interface} 2>&1 | Out-Null
        Write-Output "[#] add IPv4 default route via wireguard gateway ${ipv4} via interface index ${interface}"
    }
    catch {
        Write-Output "[#] unable to find an IPv4 for interface `"${interface}`""
    }
    try {
        $ipv6 = (Get-NetIPAddress -InterfaceIndex $interface -AddressFamily IPv6).IPAddress
        route add ::0/0 ${ipv6} METRIC 1 IF ${interface} 2>&1 | Out-Null
        Write-Output "[#] add IPv6 default route via wireguard gateway ${ipv6} via interface index ${interface}"
    }
    catch {
        Write-Output "[#] unable to find an IPv6 for interface `"${interface}`""
    }
}

function post_down() {
    if (Test-Path -PathType Leaf -Path "$PID_FILE") {
        $file_content = Get-Content -Path "${PID_FILE}"
        $file_content = $file_content.Split(" """)
        $wspid = $file_content[0]
        $remote_ip = $file_content[1]
        $gw = $file_content[2]
        $wshost = $file_content[3]
        delete_host_entry $wshost $remote_ip
        Stop-Process -ErrorAction SilentlyContinue -Force -id $wspid | Out-Null
        route delete ${remote_ip}/32 ${gw} | Out-Null
        Remove-Item -ErrorAction Continue "$PID_FILE"
    }
    else {
        # $PID_FILE does not exist !
        Write-Output "[#] Missing PID file: ${PID_FILE}"
    }
}

Invoke-Expression $FUNC
