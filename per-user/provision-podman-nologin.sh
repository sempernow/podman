#!/usr/bin/env bash
####################################################################
# Provision a stable rootless Podman environment for an AD user
# by creating a local service account (--shell /sbin/nologin),
# as which the otherwise unprivileged namesake (AD user)
# may sudo only the set of commands declared at a sudoers file
# scoped to AD group "podman-sudoers".
#
# ARGs: [DOMAIN_USER] (Default is SUDO_USER)
#
# - Idempotent
####################################################################

## Guardrails
[[ $(whoami) == 'root' ]] || {
    echo '  Must RUN AS root'

    exit 11
}
logger "Script run by '$SUDO_USER' via sudo : '$BASH_SOURCE'"

domain_user=$SUDO_USER
## Allow domain admins to select the AD user
[[ $1 ]] && groups $SUDO_USER |grep ad-linux-sudoers && domain_user=$1

app=podman
alt=/work/$app
alt_home=$alt/home/$domain_user
local_user=$app-$domain_user
local_group=$local_user

grep -e "^$domain_user" /etc/passwd && {
    echo "  This script creates a local account, '$app-$domain_user', for a *non-local* (AD domain) user."
    echo "  However, this user, '$domain_user', is *local*."
    echo "  Local users are advised to run (rootless) Podman from their existing local account."

    exit 22
}

seVerify(){
    ## Verify SELinux fcontext equivalence : "/home = $alt/home"
    semanage fcontext --list |grep "$alt" |grep "$alt/home = /home"
}
export -f seVerify

## Configure a non-standard (alt) HOME for local user which SELinux treats as it would those of /home
mkdir -p $alt/home
seVerify || {
    ## Force SELinux to accept SELinux declarations REGARDLESS of current state of SELinux objects at target(s)
    semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Delete all rules; is okay if no rules exist.
    restorecon -Rv $alt/home # Apply the above purge (now).
    ## Declare SELinux fcontext EQUIVALENCE : "/home = $alt/home"
    semanage fcontext --add --equal /home $alt/home
    restorecon -Rv $alt/home # Apply the above rule (now).
}

## Create a *regular* user (and group), having no login shell,
## yet a home directory expected by Podman's rootless (per-user) scheme.
## Podman rootless scheme expects an active login shell (DBus Session Bus, etc.),
## and so fails to provision user namespace for any --system user.
## The parameters required to satisfy Podman must be injected into the sudo session.
## See /usr/local/bin/podman script : sudo -u
id -un $local_user >/dev/null 2>&1 || {
    useradd --create-home --home-dir $alt_home --shell /sbin/nologin $local_user
    loginctl enable-linger $local_user
}
id -un $local_user >/dev/null 2>&1 || {
    echo "ERR : FAILed @ useradd : $local_user does NOT EXIST."

    exit 33
}
## Allow domain user to self-provision.
sudoers=podman-sudoers
groups $domain_user |grep $sudoers     || usermod -aG $sudoers $domain_user
## Allow domain user access to home of its provisioned local user.
groups $domain_user |grep $local_group || usermod -aG $local_group $domain_user
newgrp $local_group
chown -R $local_user:$local_group $alt_home
find $alt_home -type d -exec chmod 775 {} \+
find $alt_home -type f -exec chmod 660 {} \+

## Verify that $local_user is provisioned
restorecon -Rv $alt/home # Apply any resulting SELinux fcontext changes (again, just to be sure).
ls -ZRhl $alt
seVerify || {
    echo " ERR : FAILed @ SELinux : semanage fcontext"

    exit 66
}
grep $local_user /etc/subuid &&
    grep $local_group /etc/subgid || {
        echo "  ERR : FAILed @ subids"

        exit 77
    }

## Create "neutral" working directory
## Necessary only if HOME is not declared.
## That is, if /usr/local/bin/podman wrapper not invoked
## - Not HOME of $local_user, where $domain_user would fail AuthZ
## - Not HOME of $domain_user, where $local_user would fail AuthZ
# scratch="$alt/scratch/$domain_user"
# mkdir -p $scratch
# chown -R $domain_user:$local_user $scratch
# chmod 755 $scratch

#sudo su -u $local_user podman system migrate

## If login shell
#sudo -u $local_user podman run busybox hostname


# pushd $scratch &&
#     sudo -u $local_user /usr/bin/podman info |tee podman.info.yaml &&
#         popd

podman run --rm --volume $alt_home:/mnt/home alpine sh -c '
    echo $(whoami)@$(hostname -f)
    umask 002
    rm -f /mnt/home/test-write-access-*
    ls -hl /mnt/home
    touch /mnt/home/test-write-access-$(date -u '+%Y-%m-%dT%H.%M.%SZ')
    ls -hl /mnt/home
'
