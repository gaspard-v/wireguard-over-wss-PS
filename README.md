### Wireguard-over-Websockets Config

This project explains the steps to enable a Wireguard VPN connection to be tunnelled over a Secure Websockets (WSS) connection for use cases where outbound VPN traffic may be blocked/filtered/monitored.

The following steps assume that there is already a Wireguard connection established that is to be mondified for tunelling over WSS.

#### Server Configuration

No modifications need to be made to the Wireguard server configuration itself, but `wstunnel` needs to be installed and configured as a systemd unit.
**This version is only compatible with wstunnel version 7.x.x or higher**
**if you use wstunnel version 6.x.x or below, please use the "wstunnel-haskell" branch**

1. Download the latest wstunnel [release](https://github.com/erebe/wstunnel/releases)
2. Copy the binary to somewhere in `/usr/local/bin/wstunnel`
3. Allow the binary to listen on privileged ports:

```bash
$ sudo setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/wstunnel
```

4. Create the following service file with `systemctl edit --force --full wstunnel.service`:

```bash
[Unit]
Description=Wireguard UDP tunnel over websocket
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
ExecStart=/usr/local/bin/wstunnel server ws://0.0.0.0:80 --restrict-to 127.0.0.1:51820
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

5. Start and enable the service:

```bash
$ sudo systemctl enable wstunnel
$ sudo systemctl start wstunnel
```

If relying solely on the software firewall installed on the droplet, ensure that inbound traffic to port 443 is permitted. If relying upon DigitalOcean cloud firewall, see later steps for dynamically allowing traffic through during connection establishment using the DigitalOcean API.

#### Client Configuration

1. Execute [active_script_exec.ps1](./active_script_exec.ps1) as admin, it would allows Wireguard to execute scripts
2. Create `C:\wstunnel\bin` and add it to `PATH` [how to](https://www.architectryan.com/2018/03/17/add-to-the-path-on-windows-10/)
3. Download the latest wstunnel [release](https://github.com/erebe/wstunnel/releases)
4. Copy the binary to `C:\wstunnel\bin`
5. Copy existing config to `C:\wstunnel\wss.conf`
6. Install `wstunnel.ps1` to `C:\wstunnel\wstunnel.ps1` [(script)](./wstunnel.ps1)
7. Create a connection specific config file at `C:\wstunnel\wss.wstunnel.ps1` [(example)](./wss.wstunnel.ps1):

```
# $REMOTE_HOST and $REMOTE_PORT MUST be DEFINED !
$REMOTE_HOST='some.server.com'
$REMOTE_PORT=51820

# Override default hosts file path
# $UPDATE_HOSTS='C:\hosts\file\path'

# Change if using nginx with custom prefix for added security
# $WS_PREFIX='E7m5vGDqryd55MMP'

# Change if running WSS on a non-standard port, i.e. 4443
# $WSS_PORT=443

# Can change local port of the wstunnel, don't forget to change Peer.Endpoint
# $LOCAL_PORT=${REMOTE_PORT}
```

Next we will modify the client confg to configure routing and point at the correct endpoint for our websockets tunnel. (Or cheat, and look at the [example config](./wss.conf))

1. Ensure the `Endpoint` directive is pointing at `127.0.0.1:51820`
2. Add the following lines to the `[Interface]` section:

```
Table = off
PreUp = powershell -file C:\wstunnel\wstunnel.ps1 pre_up
PostUp = powershell -file C:\wstunnel\wstunnel.ps1 post_up
PostDown = powershell -file C:\wstunnel\wstunnel.ps1 post_down
```

#### Finish

The tunnelling should now be configured - ensure the server is running and `wstunnel` is started on the server and initiate a connection - you should then be able to see the tunnel established by running `wg`.

Ensure that all files under `/etc/wireguard` are owned by root:

```
$ chown -R root: /etc/wireguard
$ chmod 600 /etc/wireguard/*
$ chmod 700 /etc/wireguard/do-firewall.sh
```
