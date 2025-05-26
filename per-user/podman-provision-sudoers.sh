#!/usr/bin/env bash
######################################################################
# This script installs an application-scoped sudoers drop-in
# for per-user provisioning and use of Podman in rootless mode: 
# 
# - Allows (AD) users to self provision a local (proxy) user.
# - Limits runas command of proxy user to podman binary only.
#
# - Idempotent
######################################################################
set -euo pipefail

[[ $(whoami) == 'root' ]] || {
    echo '❌  Must RUN AS root' >&2

    exit 11
}

## Allow domain-users group members to self provision 
## a local-proxy user for Podman's rootless mode:
##  sudo $self_provision_script
## Allow domain-users group members to runas their local-proxy user 
## to execute the podman binary in a declared environment:
##  sudo -u $app-$USER <env_keep> /usr/bin/$app ...
app=${APP_NAME}
sudoers=/etc/sudoers.d/$app
self_provision_script=/usr/local/bin/${APP_PROVISION_USER}
domain=${SYS_GROUP_DOMAIN_USERS}
proxy=${SYS_GROUP_LOCAL_PROXY}

getent group $proxy || groupadd -r $proxy

tee $sudoers <<EOH
Defaults:%$domain secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
%$domain ALL=(ALL) $self_provision_script
Defaults:$domain env_keep += "HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS"
%$domain ALL=(:$proxy) NOPASSWD: /usr/bin/$app
EOH

chown root:root $sudoers
chmod 640 $sudoers
