#!/usr/bin/env bash
# @ /usr/local/bin/podman
#####################################################################
# This script runs /usr/bin/podman as *local* user "podman-<USER>",
# which is a local proxy for the invoking domain (AD) user (<USER>).
#
# The local-proxy user must already be configured
# to their namespaced Podman environment.
# See /usr/local/bin/provision-pddman-nologin.sh
#
# The invoking user must have membership in group "podman-sudoers"
# unless otherwise privileged with the necessary access.
#####################################################################
bin=/usr/bin/podman
[[ -f $bin ]] || exit 11

user=$(id -un)
cat /etc/passwd |grep -e "^$user:" && {
    ## If invoking user is local, then run podman directly and exit.
    /usr/bin/podman "$@"
    exit $?
}

home="$(cat /etc/passwd |grep "podman-$user:" |cut -d':' -f6)"
[[ -d $home ]] || exit 22

## Change working dir to home of local user else to unconfigured neutral dir.
[[ $(pwd) =~ $home ]] ||
    cd $home || {
        mkdir -p /tmp/$user &&
            cd /tmp/$user ||
                echo '  WARN: Unable to set the working directory'
    }

## Invoke Podman binary with all expected parameters configured to this (nologin) local user.
sudo -u podman-$user \
    HOME=$home \
    XDG_RUNTIME_DIR=/run/user/$(id -u podman-$user) \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u podman-$user)/bus \
    $bin "$@"
