#!/usr/bin/env bash
######################################################################
# This script adds the current user to Podman sudoers group,
# if current user is member of group ad-domain-users.
#
# - Idempotent
######################################################################
user=$(id -un)

## Allow only domain users to self-provision.
groups $user |grep ad-domain-users || exit 1

## Add user to the podman sudoers group
sudoers=podman-sudoers
groups $user |grep $sudoers || {
    sudo usermod -aG $sudoers $user ## MUST BE ADDED too, so this is bad idea.
}
