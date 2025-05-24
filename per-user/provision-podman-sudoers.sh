#!/usr/bin/env bash
######################################################################
# This script installs a group-scoped sudoers drop-in file
# allowing group members the declared set of sudo commands
# required for containerized development in a rootless (per-user)
# Podman environment. The group may be local or domain (AD).
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

[[ $(whoami) == 'root' ]] || {
    echo '  Must RUN AS root'

    exit 11
}

app=podman
scope=$app-sudoers
self_provision=/usr/local/bin/provision-$app-nologin.sh
sudoers=/etc/sudoers.d/$scope

getent group $scope || groupadd -r $scope

## Allow (AD) user to self provision:
##  sudo $self_provision
## Allow scoped-group member to run binary as sudo:
##  sudo -u $app-$USER $app ...
tee $sudoers <<EOH
Defaults:%$scope secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
Defaults:%$scope env_keep += "HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
%$scope ALL=(ALL) NOPASSWD: $self_provision
%$scope ALL=($app-*) NOPASSWD: /usr/bin/env, /usr/bin/$app
EOH
chown root:root $sudoers
chmod 640 $sudoers
