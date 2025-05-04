#!/usr/bin/env bash
# Provision a service account for AD users to run as (sudo su), 
# limited to running rootless podman via an account-group scoped sudoers configuration
[[ $(whoami) == 'root' ]] || { 
    echo '  Must RUN AS root'
    exit 11
}

## Create a local user account having a non-standard (alt) HOME which SELinux treats as it would those of /home
##   Attempts to configure a *system* user (-r, --system) for rootless podman fail by many layered modes.
##   Podman expects and relies upon numerous adjacent services and processes,
##   native only to *regular* user accounts, when provisioning per-user rootless containers.
u=${1:-podmaners}
g=$u
alt=/work
d=$alt/home/$u
seVerify(){
    semanage fcontext --list | grep "$alt" |grep "$alt/home = /home"
}
export -f seVerify

mkdir -p $alt/home

seVerify || {
    ## Force SELinux to accept SELinux declarations REGARDLESS of current state of SELinux objects at target(s)
    semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Delete all rules; is okay if no rules exist.
    restorecon -Rv $alt/home
    semanage fcontext --add --equal /home $alt/home # FAILs by SELinux  "equivalence" rules
    #semanage fcontext -a -t user_home_dir_t "$work(/.*)?"
    restorecon -Rv $alt/home
    #userdel -r -Z $u || userdel -Z $u
}

## Create user and group for use as the service account
id -un $u >/dev/null 2>&1 || {
    useradd --create-home --home-dir $d --shell /bin/bash $u
    loginctl enable-linger $u
}
#usermod -s /bin/bash $u
echo "$u" |sudo passwd $u --stdin
restorecon -Rv $alt/home

## Verify
seVerify || echo FAILed @ SELinux : semanage fcontext
ls -ZRhl $alt
grep $u /etc/subuid
grep $u /etc/subgid

#sudo su $u podman system migrate

## Start an SSH login session. Doing so starts the active user session:
## - Starts per-user `systemd session
## - XDG_RUNTIME_DIR, /run/user/<UID>, is created
## - session dbus is spawned
## Podman rootless per-user scheme requires all that.
ssh $u@localhost

