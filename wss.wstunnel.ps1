# $REMOTE_HOST and $REMOTE_PORT MUST be DEFINED !
$REMOTE_HOST = 'some.server.com'
$REMOTE_PORT = 51820

# Override default hosts file path
# $UPDATE_HOSTS='C:\hosts\file\path'

# Change if using nginx with custom prefix for added security
# $WS_PREFIX='E7m5vGDqryd55MMP'

# Change if running WSS on a non-standard port, i.e. 4443
# $WSS_PORT=443

# Can change local port of the wstunnel, don't forget to change Peer.Endpoint
# $LOCAL_PORT=${REMOTE_PORT}

# Wstunnel will use this proxy
# $HTTP_PROXY="http://USER:PASS@HOST:PORT"

# Override DNS resolution
# $OVERRIDE_IPv4 = ''
# $OVERRIDE_IPv6 = ''

# Path of wstunnel.exe, if not in PATH
# WSTUNNEL_EXEC_PATH = "C:\path\to\wstunnel.exe"

# disable logs (default is false)
# $DISABLE_LOGS = $true

# specify logs directory
# $LOGS_DIR = "C:\path\to\logs\directory"
