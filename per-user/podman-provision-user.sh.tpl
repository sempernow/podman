#!/usr/bin/env bash
####################################################################
# Provision a stable rootless Podman environment for an AD user
# by adding a local user ($app-$USER) having no login shell,
# to which the otherwise-unprivileged namesake will "sudo -u". 
# That local proxy's allowed commands are thereby limited 
# to those declared at an appropriate sudoers drop-in. 
# 
# RedHat has not yet documented a stable, scalable,
# fully-functional rootless Podman solution for non-local (AD) 
# users seeking a containerized-delvelopment environmnet. 
# This local-proxy scheme is a workaround.
#
# ARGs: [DOMAIN_USER] (Default is SUDO_USER)
#
# - Idempotent
####################################################################
app=APP_NAME
admins=APP_GROUP_ADMINS
app_sudoers=APP_GROUP_USERS
img=APP_OCI_TEST_IMAGE

[[ -n "${SUDO_USER:-}" ]] || {
    echo "⚠  USAGE: sudo ${BASH_SOURCE##*/}" >&2
    echo "   REQUIREs membership in GROUP: $app_sudoers" >&2

    exit 1
}
groups "${SUDO_USER:-}" |grep "$app_sudoers" || {
    echo "⚠  This script REQUIREs membership in GROUP: $app_sudoers" >&2

    exit 2
}

domain_user=$SUDO_USER
## Allow admins to select the user
[[ $1 ]] && groups $SUDO_USER |grep "$admins" && domain_user=$1

alt=/work/$app
alt_home=$alt/home/$domain_user
local_user=$app-$domain_user
local_group=$local_user

id "$local_user" >/dev/null 2>&1 && grep -qe "^$local_user" /etc/passwd && {
    echo "⚠  Local user '$local_user' already exists." >&2

    exit 11
}

logger "Script run by '$SUDO_USER' via sudo : '$BASH_SOURCE'"

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
## Allow local-proxy user to run podman wrapper script
groups "$local_user" |grep "$app_sudoers" ||
usermod -aG "$app_sudoers" $local_user

## Allow domain user to self-provision.
## Useful when the invoking user is not the target domain user, else redundant.
groups "$domain_user" |grep "$app_sudoers" || {
    usermod -aG "$app_sudoers" "$domain_user" &&
        echo "🚧  User '$domain_user' may need to LOGOUT/LOGIN to activate their membership in group '$app_sudoers'." >&2
}

## Allow domain user access to home of its proxy (provisioned local user).
groups "$domain_user" |grep "$local_group" || {
    usermod -aG "$local_group" "$domain_user" &&
        echo "🚧  User '$domain_user' may need to LOGOUT/LOGIN to activate their membership in group: '$local_group'." >&2
}

## Configure local proxy's home; podman's working directory for this user.
chown -R $local_user:$local_group $alt_home
find $alt_home -type d -exec chmod 775 {} \+
find $alt_home -type f -exec chmod 660 {} \+

## Verify that $local_user is provisioned
restorecon -Rv $alt/home # Apply any resulting SELinux fcontext changes (again, just to be sure).
ls -Zhld $alt_home
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

echo -e "\n✅  Provision complete.\n"
ok(){
    echo -e "\n✅  Container test complete.\n"
    echo "⚡  Podman ran successfully in rootless mode under your local proxy's namespace ...
    - Pulled an image from an OCI registry: '$img' .
    - Ran its container with a bind mount to your local-proxy user's home directory.
    - Created a file in the container, writing it to the mounted directory (available at the host).
        * See the file at '$alt_home/'
    "
    echo -e '🧪  Next, try ...
    home="$(getent passwd "podman-$(id -un)" |cut -d: -f6)"
    img='"$img"'
    podman run --rm --volume $home:/mnt/home $img sh -c '"'touch /mnt/home/another-test-file;ls -hl /mnt/home'"
}
## Verify that this domain user can run podman as the otherwise-unprivileged local-proxy user via the explicitly-declared wrapper script.
/usr/local/bin/podman run --rm --volume $alt_home:/mnt/home $img sh -c '
    echo "🚀  Hello from container '$(hostname -f)' running as $(whoami) (from the container's perspective) !"
    umask 002
    ls -hl /mnt/home
    touch /mnt/home/test-write-access-$(date -u '+%Y-%m-%dT%H.%M.%SZ')
    ls -hl /mnt/home
' && ok || echo "⚠  Podman's attempt to run a container in rootless mode (under the local-proxy user's namespace), having a bind-mount, has failed."

exit $?
#######

