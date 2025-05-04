#!/usr/bin/env bash
#####################################################################
# This script runs /usr/bin/podman as *local* user "podman-$USER",
# which is a local proxy for the invoking AD user ($USER).
# The local proxy must be provisioned with 
# a rootless Podman environment.
#
# See /usr/local/bin/provision
# 
# The invoking user must have membership in group "podman-sudoers"
# unless otherwise privileged with the necessary access.
#####################################################################
## Run in the workspace provisioned for this user.
## Podman's rootless scheme requires a "neutral" directory:
## - Not HOME of USER      : SUDO_USER fails AuthZ
## - Not HOME of SUDO_USER : USER fails AuthZ
scratch=/work/podman/scratch/$USER
[[ $(pwd) =~ $scratch ]] ||
    cd $scratch ||
        cd /tmp/$USER

sudo -u podman-$USER /usr/bin/podman "$@"

