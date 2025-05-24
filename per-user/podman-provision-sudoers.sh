#!/usr/bin/env bash
######################################################################
# This script installs a group-scoped sudoers drop-in files
# to provision users for Podman in rootless (per-user) mode: 
# 
# - Allows (AD) users to self provision a local proxy user.
# - Limits the proxy user to run only podman commands, 
#   and only via a script which confiugres the environment.
#
# - Idempotent
######################################################################

[[ $(whoami) == 'root' ]] || {
    echo '❌  Must RUN AS root' >&2

    exit 11
}

app=podman

## Allow (AD) user to self provision:
##  sudo $self_provision
scope=$app-provisioners
self_provision=/usr/local/bin/$app-provision-nologin.sh
sudoers=/etc/sudoers.d/$scope
getent group $scope || groupadd -r $scope
tee $sudoers <<EOH
Defaults:%$scope secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
%$scope ALL=(ALL) NOPASSWD: $self_provision
EOH
chown root:root $sudoers
chmod 640 $sudoers

## Limit the local proxy user to run only the podman binary in its declared environment:
##  sudo -u $app-$USER -- env ... $app ...
scope=$app-local
sudoers=/etc/sudoers.d/$scope
getent group $scope || groupadd -r $scope
tee $sudoers <<EOH
Defaults:%$scope secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
Defaults:%$scope env_keep += "HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
%$scope ALL=(ALL) NOPASSWD: /usr/bin/env, /usr/bin/$app
EOH
chown root:root $sudoers
chmod 640 $sudoers
