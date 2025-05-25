#!/usr/bin/env bash
######################################################################
# This script installs a group and its scoped sudoers drop-in
# for per-user provisioning and use of Podman in rootless mode: 
# 
# - Allows (AD) users to self provision a local (proxy) user.
# - Limits that proxy user to run only the podman binary.
#
# - Idempotent
######################################################################
set -euo pipefail

[[ $(whoami) == 'root' ]] || {
    echo '❌  Must RUN AS root' >&2

    exit 11
}

## Allow domain (AD) user to self provisions:
##  sudo $self_provision
## Limit local-proxy user commands to the podman binary in its declared environment:
##  sudo -u $app-$USER -- <env_keep> $app ...

app=${APP_NAME}
scope=${APP_GROUP_USERS}
self_provision=/usr/local/bin/${APP_PROVISION_USER}
sudoers=/etc/sudoers.d/$scope

getent group $scope || groupadd -r $scope

tee $sudoers <<EOH
Defaults:%$scope secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
Defaults:%$scope env_keep += "HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
%$scope ALL=(ALL) NOPASSWD: $self_provision, /usr/bin/$app
EOH

chown root:root $sudoers
chmod 640 $sudoers
