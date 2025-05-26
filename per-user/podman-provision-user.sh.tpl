#!/usr/bin/env bash
###############################################################################
# Provision a stable rootless Podman environment for a domain (AD) user
# by adding a local-proxy user ($app-$USER), having nologin shell,
# for the otherwise-unprivileged namesake to runas (sudo -u). 
# 
# This allows for further securing the local proxy by limiting the commands 
# allowed of its invoking (AD) sudoer to those declared in a sudoers drop-in. 
# That is, sudo is utilized here to limit, not to privilege.
# 
# RedHat has not yet documented a stable, scalable,
# fully-functional rootless Podman solution for non-local (AD) 
# users seeking a containerized-delvelopment environmnet. 
# This local-proxy scheme is a workaround.
#
# ARGs: [DOMAIN_USER] (Default is SUDO_USER) 
#
# - Idempotent
###############################################################################
app=APP_NAME
admins=SYS_GROUP_ADMINS
group_domain_users=SYS_GROUP_DOMAIN_USERS
group_proxy_users=SYS_GROUP_PROXY_USERS
img=APP_OCI_TEST_IMAGE

[[ -n "${SUDO_USER:-}" ]] || {
    echo "⚠  USAGE: sudo ${BASH_SOURCE##*/}" >&2
    echo "   REQUIREs membership in GROUP: '$group_domain_users'" >&2

    exit 1
}
groups "${SUDO_USER:-}" |grep "$group_domain_users" || {
    echo "⚠  This script REQUIREs membership in GROUP: '$group_domain_users'" >&2

    exit 2
}

domain_user=$SUDO_USER
## Allow admins to select the user
[[ $1 ]] && groups $SUDO_USER |grep "$admins" && domain_user=$1

alt=/work/$app
alt_home=$alt/home/$domain_user
user_local_proxy=$app-$domain_user
group_local_proxy=$user_local_proxy

id "$user_local_proxy" >/dev/null 2>&1 && grep -qe "^$user_local_proxy" /etc/passwd && {
    echo "⚠  Local user '$user_local_proxy' already exists." >&2

    exit 11
}

logger "Script run by '$SUDO_USER' via sudo : '$BASH_SOURCE'"

grep -qe "^$domain_user" /etc/passwd && {
    echo "⚠  This script creates a local-proxy account, '$app-$domain_user', for an external (AD) user." >&2
    echo "    However, this user ($domain_user) is *local*." >&2
    echo "    Local users are advised to run $app from their existing local account." >&2

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
id "$user_local_proxy" >/dev/null 2>&1 || {
    useradd --create-home --home-dir $alt_home --shell /sbin/nologin $user_local_proxy
    loginctl enable-linger "$user_local_proxy"
}
id "$user_local_proxy" >/dev/null 2>&1 || {
    echo "⚠  ERR : FAILed @ useradd : '$user_local_proxy' does NOT EXIST." >&2

    exit 33
}
## Allow domain user to runas group having local-proxy user as member
## This allows for scalable sudoers file; declare by group rather than users. 
groups "$user_local_proxy" |grep "$group_proxy_users" ||
usermod -aG "$group_proxy_users" $user_local_proxy

## Allow domain user to self-provision.
## Useful when the invoking user is not the target domain user, else redundant.
groups "$domain_user" |grep "$group_domain_users" || {
    usermod -aG "$group_domain_users" "$domain_user" &&
        echo "🚧  User '$domain_user' may need to LOGOUT/LOGIN to activate their membership in group '$group_domain_users'." >&2
}

## Allow domain user access to home of its local proxy.
groups "$domain_user" |grep "$group_local_proxy" || {
    usermod -aG "$group_local_proxy" "$domain_user" &&
        echo "🚧  User '$domain_user' may need to LOGOUT/LOGIN to activate their membership in group: '$group_local_proxy'." >&2
}

## Configure local proxy's home (podman's working directory) for R/W access by this domain user.
chown -R $user_local_proxy:$group_local_proxy $alt_home
find $alt_home -type d -exec chmod 775 {} \+
find $alt_home -type f -exec chmod 660 {} \+

## Fix and verify SELinux fcontext of the local-proxy's home
restorecon -Rv $alt/home # Apply any resulting SELinux fcontext changes (again, just to be sure).
ls -Zhld $alt_home
seVerify || {
    echo "⚠  ERR : FAILed @ SELinux : semanage fcontext" >&2

    exit 66
}

## Verify that namespaces (subids) are provisioned for the local proxy

grep -q $user_local_proxy /etc/subuid || {
    echo "⚠  ERR : FAILed to add subUID range for local-proxy user '$user_local_proxy'" >&2
    
    exit 77
}
grep -q $group_local_proxy /etc/subgid || {
    echo "⚠  ERR : FAILed to add subGID range for local-proxy group '$group_local_proxy'" >&2

    exit 78
}

echo -e "\n✅  Provision complete.\n"

## Verify that the domain user can sudo runas the local-proxy user to execute podman in rootless mode.
echo -e "📦  Verify by running a container using the transparent podman wrapper, /usr/local/bin/podman :"
su "$domain_user" -c "/usr/local/bin/podman-test.sh $alt_home $img"

exit $? 
#######
