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
# See /usr/local/bin/podman-provision-user.sh
#####################################################################
set -euo pipefail

bin=/usr/bin/podman
[[ -x $bin ]] || {
    echo "⚠  ERR: Podman binary NOT FOUND at '$bin'" >&2

    exit 11
}

# Require a podman subcommand.
[[ $# -eq 0 ]] && {
    echo "⚠  ERR: podman REQUIREs a subcommand." >&2
    echo -e "\nUSAGE : podman <subcommand> [...args]" >&2

    exit 22
}

# Set proxy user to its AD-user namesake
invoking_user="$(id -un)"
proxy_user="podman-${invoking_user}"

# Allow invoking local users to bypass wrapper logic.
grep -qe "^$invoking_user:" /etc/passwd &&
    exec "$bin" "$@"

# Validate the invoking-user's proxy.
id "$proxy_user" &>/dev/null || {
    echo "⚠  ERR: The local-proxy user '$proxy_user' of domain user '$invoking_user' does NOT EXIST." >&2
    echo "   Create it by running the provisioning script : 'APP_PROVISION_USER'" >&2

    exit 33
}

# Validate the proxy's home directory.
home="$(getent passwd "$proxy_user" |cut -d: -f6)"
[[ -z "$home" || ! -d "$home" ]] && {
    echo "⚠  ERR: Home directory '$home' for user '$proxy_user' does NOT EXIST." >&2

    exit 44
}

# Ensure working directory is within the proxy's home, else fallback safely.
[[ "$(pwd)" =~ "$home"* ]] || {
    cd "$home" 2>/dev/null || {
        mkdir -p "/tmp/${invoking_user}"
        cd "/tmp/${invoking_user}" || {
            echo '🚧  WARN: Failed to set working directory. Proceeding from "/"' >&2
            cd /
        }
    }
}

# Lookup runtime dir of proxy user (usually 1001+ range for rootless podman)
runtime_dir="/run/user/$(id -u "$proxy_user")"
dbus_socket="$runtime_dir/bus"

# Validate runtime dir exists (loginctl linger may be required).
[[ ! -d "$runtime_dir" ]] && {
    echo "⚠  ERR: Runtime directory '$runtime_dir' does not exist. Enable linger for '$proxy_user'." >&2
    echo -e "\nRun: loginctl enable-linger $proxy_user" >&2

    exit 55
}

# Log this event
logger "Script '$BASH_SOURCE' invoked by '$invoking_user' to runas 'sudo -u $proxy_user ...' with args: $*"

# Declare the per-user environment required by Podman's rootless mode.
export HOME="$home"
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$dbus_socket"
# Replace current shell with podman binary runas the proxy of this AD user.
exec sudo -u "$proxy_user" "$bin" "$@"
