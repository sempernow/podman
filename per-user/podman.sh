#!/usr/bin/env bash
#####################################################################
# This script runs /usr/bin/podman as *local* user "podman-$USER",
# which is a local proxy for the invoking AD user ($USER).
# The local proxy must be provisioned for such a rootless-Podman 
# environment. See /usr/local/bin/provision-pddman-nologin.sh
# 
# The invoking user must have membership in group "podman-sudoers"
# unless otherwise privileged with the necessary access.
#####################################################################
## Run in the workspace provisioned for this user.
## Podman's rootless scheme requires a "neutral" directory:
## - Not HOME of USER, where SUDO_USER would fail AuthZ.
## - Not HOME of SUDO_USER, where USER would fail AuthZ.
scratch=/work/podman/scratch/$USER # The preferred neutral workspace
[[ $(pwd) =~ $scratch ]] ||
    cd $scratch ||
        cd /tmp/$USER

#sudo -u podman-$USER /usr/bin/podman "$@"

sudo -u podman-$USER \
    HOME=/work/podman/home/$USER \
    XDG_RUNTIME_DIR=/run/user/$(id -u podman-$USER) \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u podman-$USER)/bus \
    /usr/bin/podman "$@"
