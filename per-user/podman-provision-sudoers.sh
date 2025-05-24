#!/usr/bin/env bash
######################################################################
# This script installs a group-scoped sudoers drop-in file
# to provision users for Podman in rootless (per-user) mode: 
# 
# - Allows (AD) users to self provision a local proxy user.
# - Limits the proxy user to run only podman commands, 
#   and only via a script which confiugres the environment.
#
# - Idempotent
######################################################################

[[ $(whoami) == 'root' ]] || {
    echo '  Must RUN AS root'

    exit 11
}

app=podman
scope=$app-sudoers
self_provision=/usr/local/bin/$app-provision-nologin.sh
sudoers=/etc/sudoers.d/$scope

getent group $scope || groupadd -r $scope

## Allow (AD) user to self provision:
##  sudo $self_provision
## Allow scoped-group sudoers to run binary as sudo:
##  sudo -u $app-$USER -- env ... $app ...
tee $sudoers <<EOH
Defaults:%$scope secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
Defaults:%$scope env_keep += "HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
%$scope ALL=(ALL) NOPASSWD: $self_provision
%$scope ALL=($app-*) NOPASSWD: /usr/bin/env, /usr/bin/$app
EOH
chown root:root $sudoers
chmod 640 $sudoers
