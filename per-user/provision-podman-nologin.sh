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
logger "Script run by '$SUDO_USER' via sudo : '$BASH_SOURCE'"

domain_user=$SUDO_USER
## Allow domain admins to select the AD user
admins_group=ad-linux-sudoers
[[ $1 ]] && groups $SUDO_USER |grep "$admins_group" && domain_user=$1

app=podman
alt=/work/$app
alt_home=$alt/home/$domain_user
local_user=$app-$domain_user
local_group=$local_user

grep -e "^$domain_user" /etc/passwd && {
    echo "⚠  This script creates a local account, '$app-$domain_user', for a *non-local* (AD domain) user."
    echo "    However, this user, '$domain_user', is *local*."
    echo "    Local users are advised to run (rootless) Podman from their existing local account."

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
## (See podman wrapper: /usr/local/bin/podman .)
id -un $local_user >/dev/null 2>&1 || {
    useradd --create-home --home-dir $alt_home --shell /sbin/nologin $local_user
    loginctl enable-linger $local_user
}
id -un $local_user >/dev/null 2>&1 || {
    echo "⚠ ERR : FAILed @ useradd : $local_user does NOT EXIST."

    exit 33
}
## Allow domain user to self-provision.
sudoers=podman-sudoers
groups $domain_user |grep $sudoers     || usermod -aG $sudoers $domain_user
## Allow domain user access to home of its provisioned local user.
groups $domain_user |grep $local_group || usermod -aG $local_group $domain_user &&
    echo "🚧 User '$domain_user' MUST LOGOUT/LOGIN to activate their membership in groups: '$sudoers' and '$local_group'."

chown -R $local_user:$local_group $alt_home
find $alt_home -type d -exec chmod 775 {} \+
find $alt_home -type f -exec chmod 660 {} \+

## Verify that $local_user is provisioned
restorecon -Rv $alt/home # Apply any resulting SELinux fcontext changes (again, just to be sure).
ls -ZRhl $alt
seVerify || {
    echo "⚠ ERR : FAILed @ SELinux : semanage fcontext"

    exit 66
}

grep -q $local_user /etc/subuid &&
    grep -q $local_group /etc/subgid || {
        echo "⚠ ERR : FAILed @ subids"

        exit 77
    }

img=alpine
podman run --rm --volume $alt_home:/mnt/home $img -- sh -c '
    echo "🚀 Hello from $(whoami) in container $(hostname -f)!"
    umask 002
    ls -hl /mnt/home
    touch /mnt/home/test-write-access-$(date -u '+%Y-%m-%dT%H.%M.%SZ')
    ls -hl /mnt/home
'

echo "✅ Provision complete."
exit 0