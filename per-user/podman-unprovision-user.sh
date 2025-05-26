#!/usr/bin/env bash
#####################################################################################
# Teardown Podman configuration of the declared *domain* user ($1) else $SUDO_USER .
# - Affects only the *local* proxy user of that namesake : podman-<USER>.
# - Affects nothing if local namesake does not exist.
# - Deletes *local* user and group : podman-<USER>.
# - Deletes subids provisioned for that local UID:GID if exist : podman-<USER>.
# - Deletes their provisioned directories : /work/podman/{home,scratch}/podman-<USER>.
#
# ARGs: DOMAIN_USER (Defaults to SUDO_USER)
#
# - Idempotent
#
# User/group deletion targets are assured *local* and of name "$app-*".
# The target local (AD proxy) user/group is intentionally *not* verified 
# to allow for multiple runs on cleanup of any cruft from edge cases.
#####################################################################################

[[ "$(whoami)" == 'root' ]] || {
    echo '❌  Must RUN AS root' >&2

    exit 11
}

[[ "$1" ]] && domain_user="$1" || domain_user="$SUDO_USER"

#sudoers=${SYS_GROUP_DOMAIN_USERS}
app=$APP_NAME
alt=/work/$app
alt_home=$alt/home/$domain_user
user_local_proxy="$app-$domain_user"
group_local_proxy="$user_local_proxy"
group_proxy_users=$SYS_GROUP_PROXY_USERS

## Disable linger (process)
loginctl disable-linger "$user_local_proxy" 2>/dev/null # Ok if not exist

sleep 1

## Remove domain user from its local-proxy group
gpasswd -d "$domain_user" $user_local_proxy 2>/dev/null

## Delete local-proxy user
grep -qe "^$user_local_proxy" /etc/passwd && {
    userdel -r -Z "$user_local_proxy" 2>/dev/null ||
        userdel -Z "$user_local_proxy" 2>/dev/null
}
## Delete local-proxy group
grep -qe "^$group_local_proxy" /etc/group &&
    groupmems --group "$group_local_proxy" --purge &&
        groupdel "$group_local_proxy"

## Delete all fcontext rules
#semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Ok if none exist.
#restorecon -Rv $alt/home

rm -rf "$alt_home" # Should already be deleted by userdel.

## Delete the neutral working directory
rm -rf "$alt/scratch/$domain_user"

## Verify
grep -qe "^$user_local_proxy" /etc/passwd &&
    echo "❌  ERR : User '$user_local_proxy' remains" &&
        exit 71

grep -qe "^$group_local_proxy" /etc/group &&
    echo "❌  ERR : Group '$group_local_proxy' remains'" &&
        exit 74

ls -d $alt_home >/dev/null 2>&1 &&
    echo "❌  ERR : HOME dir remains for deleted local-proxy user '$user_local_proxy'" && 
        exit 76

## The subids should already be removed, but this is safety net.
## - Prefer to rerun script until successful, so commented out.
# sed -i "/^$user_local_proxy:/d" /etc/subuid
# sed -i "/^$group_local_proxy:/d" /etc/subgid

grep -qe "^$user_local_proxy" /etc/subuid &&
    echo "❌  ERR : subUID entries remain for deleted user '$user_local_proxy'" &&
        exit 78

grep -qe "^$group_local_proxy" /etc/subgid &&
    echo "❌  ERR : subGID entries remain for deleted group '$group_local_proxy'" &&
        exit 79

loginctl user-status "$user_local_proxy" 2>/dev/null |command grep -q Linger &&
    echo "❌  ERR : Linger remains enabled for '$group_local_proxy'" &&
        exit 80 ||
            echo "✅  Teardown of '$user_local_proxy' and artifacts is complete."
