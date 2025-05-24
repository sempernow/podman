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
# That target local (AD proxy) user/group is intentionally *not* verified 
# to allow for multiple runs on cleanup of any cruft from edge cases.
#####################################################################################

[[ "$(whoami)" == 'root' ]] || {
    echo '❌  Must RUN AS root'

    exit 11
}

[[ "$1" ]] && domain_user="$1" || domain_user="$SUDO_USER"

app=podman
alt=/work/$app
alt_home=$alt/home/$domain_user
local_user="$app-$domain_user"
local_group="$local_user"

echo "alt         : '$alt'"
echo "alt_home    : '$alt_home'"
echo "local user  : '$local_user'"
echo "local_group : '$local_group'"
echo "domain_user : '$domain_user'"

## Disable linger (process)
loginctl disable-linger "$local_user" 2>/dev/null # Ok if not exist

# Delete local user
grep -qe "^$local_user" /etc/passwd &&
    userdel -r -Z "$local_user" 2>/dev/null ||
        userdel -Z "$local_user" 2>/dev/null

# Delete local group
grep -qe "^$local_group" /etc/group &&
    groupmems --group "$local_group" --purge &&
        groupdel "$local_group"

# Remove from sudoers group
sudoers=podman-sudoers
gpasswd -d "$domain_user" $sudoers

## Delete all fcontext  rules
#semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Ok if none exist.
#restorecon -Rv $alt/home

rm -rf "$alt_home" # Should already be deleted by userdel.

## Delete the neutral working directory
rm -rf "$alt/scratch/$domain_user"

## Verify
grep -qe "^$local_user" /etc/passwd &&
    echo "❌  ERR : User '$local_user' remains" &&
        exit 71

grep -qe "^$local_group" /etc/group &&
    echo "❌  ERR : Group '$local_group' remains'" &&
        exit 74

ls -ZRahl $alt |grep "$local_user" &&
    echo "❌  ERR : HOME dir remains for deleted user '$local_user'" && 
        exit 76

# ## The subids should already be removed, but this is safety net
# sed -i "/^$local_user:/d" /etc/subuid
# sed -i "/^$local_group:/d" /etc/subgid
sleep 1

grep -qe "^$local_user" /etc/subuid &&
    echo "❌  ERR : subUID entries remain for deleted user '$local_user'" &&
        exit 78

grep -qe "^$local_group" /etc/subgid &&
    echo "❌  ERR : subGID entries remain for deleted group '$local_group'" &&
        exit 79

loginctl user-status "$local_user" 2>/dev/null |command grep -q Linger &&
    echo "❌  ERR : Linger remains enabled for '$local_group'" &&
        exit 80 ||
            echo "✅  Teardown of '$local_user' and artifacts is complete."
