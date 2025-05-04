#!/usr/bin/env bash
## Destroy the target user, group
## Podman deletes its namespace entries (subuid, subgid)
[[ $(whoami) == 'root' ]] || { 
    echo '  Must RUN AS root'
    exit 11
}
[[ $1 ]] && subject=$1 || subject=$SUDO_USER

app=podman
alt=/work/$app
d=$alt/home/$subject
u=$app-$subject
g=$u

## Disable linger (process)
loginctl disable-linger $u 2>/dev/null # Ok if not exist
userdel -r -Z $u 2>/dev/null ||
    userdel -Z $u 2>/dev/null

getent group $u &&
    groupmems --group $u --purge &&
        groupdel $u

## Delete all fcontext  rules
#semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Ok if none exist.
#restorecon -Rv $alt/home

rm -rf $d # Should already be deleted by userdel.

## Delete the neutral working directory
rm -rf $alt/scratch/$subject

## Verify
grep $u /etc/passwd && echo "ERR : User '$u' remains" && exit 95
getent group $u |grep $u && echo "ERR : Group '$u' remains'" && exit 96
ls -ZRahl $alt  |grep $u && echo "ERR : HOME directory remains for deleted user '$u'" &&  exit 97
#id -un $u 2>/dev/null && grep $u /etc/subuid
#id -gn $u 2>/dev/null && grep $u /etc/subgid
grep $u /etc/subuid && echo "ERR : subuid entries remain for deleted user '$u'" && exit 98
grep $u /etc/subgid && echo "ERR : subgid entries remain for deleted group '$u'" && exit 99

loginctl user-status $u 2>/dev/null |command grep Linger && exit 999 || echo ok
