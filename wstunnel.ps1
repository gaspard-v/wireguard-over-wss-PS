﻿#Requires -RunAsAdministrator

Param(
 [Parameter(Mandatory)]
 [string]
 $FUNC
)

$ErrorActionPreference = "Stop"

$WG = $env:WIREGUARD_TUNNEL_NAME

$DEFAULT_HOSTS_FILE="${Env:SystemRoot}\system32\drivers\etc\hosts"
$CFG = "$PSScriptRoot\${WG}.wstunnel.ps1"
$APPDATA = "${env:LOCALAPPDATA}\wstunnel"
$PID_FILE = "${APPDATA}\${WG}.pid"

if(-not (Test-Path -PathType Leaf -Path $CFG))
{
    throw "[#] missing config file: `"${CFG}`""
}

. "$CFG"

if (-not ($UPDATE_HOSTS))
{
    $UPDATE_HOSTS = $DEFAULT_HOSTS_FILE
}


function add_host_entry([string] $current_host, [string] $current_ip)
{
    Write-Output "[#] Add new entry ${current_host} => <${current_ip}>"
    "`n${current_ip}`t${current_host}" | Out-File -Append -Encoding utf8 -NoNewline -FilePath $UPDATE_HOSTS
}

function update_host_entry([string] $current_host, [string] $current_ip)
{
    $file_content = Get-Content "$UPDATE_HOSTS"
    [string] $content = ""
    foreach($line in $file_content) {
        if($line -match $current_host)
        {
            Write-Output "[#] Updating ${current_host} -> ${current_ip}"
            $content += "${current_ip}`t${current_host}`n"
        } else {
            $content += "${line}`n"
        }
    }
    $content.Substring(0, $content.Length-1) | Out-File -NoNewline -Encoding utf8 "$UPDATE_HOSTS"
}

function delete_host_entry([string] $current_host, [string] $current_ip)
{
    $file_content = Get-Content "$UPDATE_HOSTS"
    [string] $content = ""
    Write-Output "[#] delete entry ${current_host} -> ${current_ip}"
    foreach($line in $file_content) {
        if($line -notmatch $current_host)
        {
            $content += "${line}`n"
        }
    }
    $content.Substring(0, $content.Length-1) | Out-File -NoNewline -Encoding utf8 "$UPDATE_HOSTS"
}

function maybe_update_host([string] $current_host, [string] $current_ip)
{
    if([ipaddress]::TryParse("$current_host",[ref][ipaddress]::Loopback))
    {
        # the $current_host is a loopback ip address
        Write-Output "[#] ${current_host} is an IP address"
        return
    }
    $file_content = Get-Content "$UPDATE_HOSTS"
    if($file_content -match $current_host)
    {
        update_host_entry $current_host $current_ip
    } else {
        add_host_entry $current_host $current_ip
    }
}

function bg([string] $prog, [string[]] $params)
{
    return Start-Process -NoNewWindow -FilePath $prog -ArgumentList $params -PassThru
}

function launch_wstunnel()
{
    $rport = $REMOTE_PORT
    if ($LOCAL_PORT)
    {
        $lport = $LOCAL_PORT
    } else {
        $lport = $rport
    }
    if ($WSS_PORT) {
        $wssport=$WSS_PORT
    } else {
        $wssport=443
    }
    $param = @("--quiet", 
              "--udpTimeoutSec -1",
              "--udp"
              "-L 127.0.0.1:${lport}:127.0.0.1:${rport}",
              "wss://${REMOTE_HOST}:$wssport")
    if($WS_PREFIX)
    {
        $param += "--upgradePathPrefix ${WS_PREFIX}"
    }
    return (bg -prog "wstunnel" -params $param).id
}

function pre_up() {
    try {
        $remote_ip = [System.Net.Dns]::GetHostAddresses($REMOTE_HOST)
        $remote_ip = $remote_ip.IPAddressToString
    } catch {
        $remote_ip = [IPAddress] $REMOTE_HOST
    }
    maybe_update_host -current_host $REMOTE_HOST -current_ip $remote_ip
    # Find out the current route to $remote_ip and make it explicit
    [string] $gw = (Find-NetRoute -RemoteIPAddress $remote_ip).NextHop
    $gw = $gw.Trim()
    route add ${remote_ip}/32 ${gw} | Out-Null
    $wspid = launch_wstunnel
    New-Item -Path "${APPDATA}" -Force -ItemType "directory" | Out-Null
    "${wspid} ${remote_ip} ${gw} ${REMOTE_HOST}" | Out-File -NoNewline -FilePath "${PID_FILE}"
}

function post_up()
{
    $interface = (Get-NetAdapter -Name "${WG}*").ifIndex
    try {
        $ipv4 = (Get-NetIPAddress -InterfaceIndex $interface -AddressFamily IPv4).IPAddress
        route add 0.0.0.0/0 ${ipv4} METRIC 1 IF ${interface} 2>&1 | Out-Null
    } catch{
        Write-Output "unable to find an IPv4 for interface `"${interface}`""
    }
    try {
        $ipv6 = (Get-NetIPAddress -InterfaceIndex $interface -AddressFamily IPv6).IPAddress
        route add ::0/0 ${ipv6} METRIC 1 IF ${interface} 2>&1 | Out-Null
    } catch{
        Write-Output "unable to find an IPv6 for interface `"${interface}`""
    }
}

function post_down()
{
    if (Test-Path -PathType Leaf -Path "$PID_FILE")
    {
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
    } else {
        # $PID_FILE does not exist !
        Write-Output "[#] Missing PID file: ${PID_FILE}"
    }
}

Invoke-Expression $FUNC
