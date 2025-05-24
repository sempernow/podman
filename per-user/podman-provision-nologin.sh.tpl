#!/usr/bin/env bash
####################################################################
# Provision a stable rootless Podman environment for an AD user
# by creating a local service account (--shell /sbin/nologin)
# that allows the otherwise unprivileged namesake (AD user)
# to run as, with commands limited by an apropos sudoers file. 
#
# RedHat has not yet documented a stable, scalable,
# fully-functional rootless Podman solution 
# for remote (AD) users. This scheme is a workaround.
#
# ARGs: [DOMAIN_USER] (Default is SUDO_USER)
#
# - Idempotent
####################################################################
admins_group=APP_GROUP_ADMINS
app=APP_NAME
sudoers_provisioners=APP_GROUP_PROVISIONERS
sudoers_local_proxy=APP_GROUP_LOCAL_PROXY
img=APP_OCI_TEST_IMAGE

[[ -n "${SUDO_USER:-}" ]] || {
    echo "⚠  USAGE: sudo ${BASH_SOURCE##*/}" >&2

    exit 1
}
logger "Script run by '$SUDO_USER' via sudo : '$BASH_SOURCE'"

domain_user=$SUDO_USER
## Allow domain admins to select the AD user
[[ $1 ]] && groups $SUDO_USER |grep "$admins_group" && domain_user=$1

alt=/work/$app
alt_home=$alt/home/$domain_user
local_user=$app-$domain_user
local_group=$local_user

id "$local_user" >/dev/null 2>&1 && grep -qe "^$local_user" /etc/passwd && {
    echo "⚠  Local user '$local_user' already exists." >&2

    exit 11
}

grep -qe "^$domain_user" /etc/passwd && {
    echo "⚠  This script creates a local account, '$app-$domain_user', for a *non-local* (AD domain) user." >&2
    echo "    However, this user ($domain_user) is *local*." >&2
    echo "    Local users are advised to run (rootless) Podman from their existing local account." >&2

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
id "$local_user" >/dev/null 2>&1 || {
    useradd --create-home --home-dir $alt_home --shell /sbin/nologin $local_user
    loginctl enable-linger "$local_user"
}
id "$local_user" >/dev/null 2>&1 || {
    echo "⚠  ERR : FAILed @ useradd : '$local_user' does NOT EXIST." >&2

    exit 33
}
## Allow local proxy to run podman wrapper script
usermod -aG "$sudoers_local_proxy" $local_user

## Allow domain user to self-provision.
groups "$domain_user" |grep $sudoers_provisioners ||
    usermod -aG "$sudoers_provisioners" "$domain_user"

## Allow domain user access to home of its provisioned local user.
groups "$domain_user" |grep $local_group ||
    usermod -aG "$local_group" "$domain_user" &&
        echo "🚧  User '$domain_user' MUST LOGOUT/LOGIN to activate their membership in groups: '$sudoers' and '$local_group'." >&2

## Configure local proxy's home; podman's working directory for this user.
chown -R $local_user:$local_group $alt_home
find $alt_home -type d -exec chmod 775 {} \+
find $alt_home -type f -exec chmod 660 {} \+

## Verify that $local_user is provisioned
restorecon -Rv $alt/home # Apply any resulting SELinux fcontext changes (again, just to be sure).
ls -ZRhl $alt
seVerify || {
    echo "⚠  ERR : FAILed @ SELinux : semanage fcontext" >&2

    exit 66
}

grep -q $local_user /etc/subuid || {
    echo "⚠  ERR : FAILed to add subUID range for local user '$local_user'" >&2
    
    exit 77
}
grep -q $local_group /etc/subgid || {
    echo "⚠  ERR : FAILed to add subGID range for local group '$local_group'" >&2

    exit 78
}

## Verify that this domain user can run podman as the local-proxy user via the wrapper.
/usr/local/bin/podman run --rm --volume $alt_home:/mnt/home $img sh -c '
    echo "🚀  Hello from the container : $(whoami)@$(hostname -f) !"
    umask 002
    ls -hl /mnt/home/test-*
    touch /mnt/home/test-write-access-$(date -u '+%Y-%m-%dT%H.%M.%SZ')
    ls -hl /mnt/home/test-*
'

echo "✅  Provision complete."
exit 0