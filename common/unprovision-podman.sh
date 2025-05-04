#!/usr/bin/env bash
## Destroy the target user, group
## Podman deletes its namespace entries (subuid, subgid)
[[ $(whoami) == 'root' ]] || { 
    echo '  Must RUN AS root'
    exit 11
}

u=${1:-podmaners}
g=$u
alt=/work
d=$alt/home/$u
# Disable linger (process)
loginctl disable-linger $u 2>/dev/null # Ok if not exist
userdel -r -Z $u 2>/dev/null ||
    userdel -Z $u 2>/dev/null

getent group $u &&
    groupmems --group $u --purge &&
        groupdel $u

# Delete all fcontext  rules
semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Ok if none exist.
restorecon -Rv $alt/home

rm -rf $alt/home/$u # Should already be deleted by userdel.
sleep 1

## Verify
grep $u /etc/passwd && echo "ERR : User '$u' remains"
getent group $u |grep $u && echo "ERR : Group '$u' remains'"
ls -ZRahl $alt  |grep $u && echo "ERR : HOME directory remains for deleted user '$u'"
#id -un $u 2>/dev/null && grep $u /etc/subuid
#id -gn $u 2>/dev/null && grep $u /etc/subgid
grep $u /etc/subuid && echo "ERR : subuid entries remain for deleted user '$u'"
grep $u /etc/subgid && echo "ERR : subgid entries remain for deleted group '$u'"

loginctl user-status $u 2>/dev/null |command grep Linger
