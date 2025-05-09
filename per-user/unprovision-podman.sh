#!/usr/bin/env bash
## Destroy the target user, group
## Podman deletes its namespace entries (subuid, subgid)
[[ $(whoami) == 'root' ]] || { 
    echo '  Must RUN AS root'
    exit 11
}
[[ $1 ]] && domain_user=$1 || domain_user=$SUDO_USER

app=podman
alt=/work/$app
alt_home=$alt/home/$domain_user
local_user=$app-$domain_user
local_group=$local_user

## Disable linger (process)
loginctl disable-linger $local_user 2>/dev/null # Ok if not exist
userdel -r -Z $local_user 2>/dev/null ||
    userdel -Z $local_user 2>/dev/null

getent group $local_group &&
    groupmems --group $local_group --purge &&
        groupdel $local_group

## Delete all fcontext  rules
#semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Ok if none exist.
#restorecon -Rv $alt/home

rm -rf $alt_home # Should already be deleted by userdel.

## Delete the neutral working directory
rm -rf $alt/scratch/$domain_user

## Verify
grep $local_user /etc/passwd && echo "ERR : User '$local_user' remains" && exit 95
getent group $local_group |grep $local_user && echo "ERR : Group '$local_group' remains'" && exit 96
ls -ZRahl $alt  |grep $local_user && echo "ERR : HOME directory remains for deleted user '$local_user'" &&  exit 97
#id -un $local_user 2>/dev/null && grep $local_user /etc/subuid
#id -gn $local_user 2>/dev/null && grep $local_user /etc/subgid
grep $local_user /etc/subuid && echo "ERR : subuid entries remain for deleted user '$local_user'" && exit 98
grep $local_group /etc/subgid && echo "ERR : subgid entries remain for deleted group '$local_group'" && exit 99

loginctl user-status $local_user 2>/dev/null |command grep Linger && exit 999 || echo ok
