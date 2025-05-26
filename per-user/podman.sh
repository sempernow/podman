#!/usr/bin/env bash
######################################################################
# DO NOT MODIFY : ARTIFACT of 'podman.sh.tpl' @ 931be0c
######################################################################
set -euo pipefail
bin=/usr/bin/podman
[[ -x $bin ]] || {
    echo "⚠  ERR: Podman binary NOT FOUND at '$bin'" >&2
    exit 11
}
[[ $# -eq 0 ]] && {
    echo "⚠  ERR: podman REQUIREs a subcommand." >&2
    echo -e "\nUSAGE : podman <subcommand> [...args]" >&2
    exit 22
}
invoking_user="$(id -un)"
proxy_user="podman-${invoking_user}"
grep -qe "^$invoking_user:" /etc/passwd &&
    exec "$bin" "$@"
id "$proxy_user" &>/dev/null || {
    echo "⚠  ERR: The local-proxy user '$proxy_user' of domain user '$invoking_user' does NOT EXIST." >&2
    echo "   Create it by running the provisioning script : 'podman-provision-user.sh'" >&2
    exit 33
}
home="$(getent passwd "$proxy_user" |cut -d: -f6)"
[[ -z "$home" || ! -d "$home" ]] && {
    echo "⚠  ERR: Home directory '$home' for user '$proxy_user' does NOT EXIST." >&2
    exit 44
}
[[ "$(pwd)" =~ "$home"* ]] || {
    cd "$home" 2>/dev/null || {
        mkdir -p "/tmp/${invoking_user}"
        cd "/tmp/${invoking_user}" || {
            echo '🚧  WARN: Failed to set working directory. Proceeding from "/"' >&2
            cd /
        }
    }
}
runtime_dir="/run/user/$(id -u "$proxy_user")"
dbus_socket="$runtime_dir/bus"
[[ ! -d "$runtime_dir" ]] && {
    echo "⚠  ERR: Runtime directory '$runtime_dir' does not exist. Enable linger for '$proxy_user'." >&2
    echo -e "\nRun: loginctl enable-linger $proxy_user" >&2
    exit 55
}
logger "Script '$BASH_SOURCE' was invoked by '$invoking_user' to run 'sudo -u $proxy_user ...' with args: $*"
export HOME="$home"
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$dbus_socket"
exec sudo -u "$proxy_user" "$bin" "$@"
