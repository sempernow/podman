#!/usr/bin/env bash
######################################################################
# This script adds the current user to Podman sudoers group,
# if current user is member of group ad-domain-users.
#
# - Idempotent
######################################################################
user=$(id -un)

## Allow only domain users to self-provision.
allow=ad-domain-users
groups $user |grep $allow || {
    echo "User must be a member of group '$allow' to be allowed into this sudoers group"
    exit 1
}

## Add user to the podman sudoers group
sudoers=podman-sudoers
groups $user |grep $sudoers || {
    usermod -aG $sudoers $user ## MUST BE ADDED too, so this is bad idea.
}
