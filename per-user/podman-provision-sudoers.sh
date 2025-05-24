#!/usr/bin/env bash
######################################################################
# This script installs groups and their scoped sudoers drop-in files
# for per-user provisioning and use of Podman in rootless mode: 
# 
# - Allows (AD) users to self provision a local (proxy) user.
# - Limits that proxy user to run only env and podman binaries, 
#   and the latter only from a declared script.
#
# - Idempotent
######################################################################
set -euo pipefail

[[ $(whoami) == 'root' ]] || {
    echo '❌  Must RUN AS root' >&2

    exit 11
}

app=${APP_NAME}

## Allow (AD) user to self provision:
##  sudo $self_provision
scope=${APP_GROUP_PROVISIONERS}
self_provision=/usr/local/bin/${APP_PROVISION_NOLOGIN}
sudoers=/etc/sudoers.d/$scope
getent group $scope || groupadd -r $scope
tee $sudoers <<EOH
Defaults:%$scope secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
%$scope ALL=(ALL) NOPASSWD: /usr/bin/env, $self_provision
EOH
chown root:root $sudoers
chmod 640 $sudoers

## Limit the local proxy user to run only the podman binary in its declared environment:
##  sudo -u $app-$USER -- env ... $app ...
scope=${APP_GROUP_LOCAL_PROXY}
sudoers=/etc/sudoers.d/$scope
getent group $scope || groupadd -r $scope
tee $sudoers <<EOH
Defaults:%$scope secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
Defaults:%$scope env_keep += "HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
%$scope ALL=(ALL) NOPASSWD: /usr/bin/env, /usr/bin/$app
EOH
chown root:root $sudoers
chmod 640 $sudoers
