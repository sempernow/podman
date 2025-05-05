#!/usr/bin/env bash
######################################################################
# This script installs a group-scoped sudoers drop-in file.
# allowing group members the declared set of sudo commands
# required for containerized development in a rootless (per-user)
# Podman environment. The group may be local or remote (AD).
#
# Group membership must include *local* users, "podman-<USER>",
# each created as a logical mapping of its AD-user namesake.
# Unlike their AD counterparts, these local-proxy users may be
# configured to satisfy all process requirements
# of Podman's rootless scheme.
#
# RedHat has not yet documented a stable, fully-functional rootless
# Podman solution for remote (AD) users.
#
# - Idempotent
######################################################################

## Guardrails
[[ $(whoami) == 'root' ]] || { 
    echo '  Must RUN AS root'
    
    exit 11
}

app=podman
scope=$app-sudoers
script=/usr/local/bin/provision-podman-nologin.sh
sudoers=/etc/sudoers.d/$scope

getent group $scope || groupadd -r $scope

## Allow user to self provision (1.) and to run any podman command (2.) :
## 1. sudo $script
## 2. sudo -u podman-$USER podman ...
[[ -f $sudoers ]] || tee $sudoers <<EOH
Defaults:%$scope secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
Defaults:%$scope env_keep += "HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
%$scope ALL=(ALL) NOPASSWD: $script, /usr/bin/podman *, /usr/local/bin/podman *
EOH

