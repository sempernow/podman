#!/usr/bin/env bash
# @ /usr/local/bin/podman
#####################################################################
# This script runs /usr/bin/podman as *local* user "podman-<USER>",
# which is a local proxy for the invoking domain (AD) user (<USER>).
#
# The local-proxy user must be configured
# to their namespaced Podman environment, 
# and privileged with the required access.
#
# See /usr/local/bin/provision-podman-nologin.sh
#####################################################################
set -euo pipefail

bin=/usr/bin/podman
[[ -x $bin ]] || {
    echo "ERR: Podman binary not found at $bin" >&2

    exit 11
}

# Require a podman subcommand.
[[ $# -eq 0 ]] && {
    echo "ERR: No podman subcommand provided." >&2
    echo "Usage: podman <subcommand> [...args]" >&2

    exit 22
}

invoking_user="$(id -un)"
proxy_user="podman-${invoking_user}"

# Allow local users to bypass wrapper logic.
grep -qe "^$invoking_user:" /etc/passwd &&
    exec "$bin" "$@"

# Validate the invoking-user's proxy.
id "$proxy_user" &>/dev/null || {
    echo "ERR: Proxy user '$proxy_user' does not exist. Run the provisioning script first." >&2

    exit 33
}

# Validate the proxy's home directory.
home="$(getent passwd "$proxy_user" |cut -d: -f6)"
[[ -z "$home" || ! -d "$home" ]] && {
    echo "ERR: Home directory '$home' for user '$proxy_user' does not exist" >&2

    exit 44
}

# Ensure working directory is within the proxy's home, else fallback safely.
[[ "$(pwd)" != "$home"* ]] || {
    cd "$home" 2>/dev/null || {
        mkdir -p "/tmp/${invoking_user}"
        cd "/tmp/${invoking_user}" || {
            echo 'WARN: Failed to set working directory. Proceeding from /' >&2
            cd /
        }
    }
}

# Lookup runtime dir of proxy user (usually 1001+ range for rootless podman)
runtime_dir="/run/user/$(id -u "$proxy_user")"
dbus_socket="$runtime_dir/bus"

# Validate runtime dir exists (loginctl linger may be required).
[[ ! -d "$runtime_dir" ]] && {
    echo "ERR: Runtime directory $runtime_dir does not exist. Enable linger for $proxy_user." >&2
    echo "Run: loginctl enable-linger $proxy_user" >&2

    exit 55
}

# Log meta of the subsequent exec.
logger "Invoked by '$invoking_user' via sudo as '$proxy_user' : Script: '$BASH_SOURCE'"
echo "Invoked by $invoking_user : Switching to $proxy_user with args: $*" >&2

# Execute podman as the proxy user in the environment required by Podman's rootless scheme.
exec sudo -u "$proxy_user" -- \
    HOME="$home" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$dbus_socket" \
    "$bin" "$@"
