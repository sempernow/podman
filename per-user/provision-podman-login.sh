#!/usr/bin/env bash
###########################################################################
# Provision a stable rootless Podman environment for an AD user
# by creating a locked local user account for AD user to run as,
# only by key-based AuthN via SSH tunnel.
# - Idempotent
###########################################################################

## Guardrails
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

grep -e "^$subject" /etc/passwd && {
    echo "  This script provisions a local account, '$u', only for a *non-local* (AD) user."
    echo "  However, this subject user, '$subject', is local. (See /etc/passwd)"
    echo "  Local users are advised to run (rootless) Podman from their existing local account."
    
    exit 22
}

## Create a local user account having a non-standard (alt) HOME which SELinux treats as it would those of /home
##   Attempts to configure a *system* user (-r, --system) for rootless podman fail by many layered modes.
##   Podman expects and relies upon numerous adjacent services and processes,
##   available only to *regular* local user accounts, when provisioning per-user rootless containers.
seVerify(){
    ## Verify SELinux fcontext equivalence : "/home = $alt/home"
    semanage fcontext --list | grep "$alt" |grep "$alt/home = /home"
}
export -f seVerify

mkdir -p $alt/home
seVerify || {
    ## Force SELinux to accept SELinux declarations REGARDLESS of current state of SELinux objects at target(s)
    semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Delete all rules; is okay if no rules exist.
    restorecon -Rv $alt/home # Apply the above purge (now).
    ## Declare SELinux fcontext equivalence : "/home = $alt/home"
    semanage fcontext --add --equal /home $alt/home 
    restorecon -Rv $alt/home # Apply the above rule (now).
}

## Create user and group for use as local account for $subject
id -un $u >/dev/null 2>&1 || {
    useradd --create-home --home-dir $d --shell /bin/bash $u
    loginctl enable-linger $u
}
#usermod -s /bin/bash $u
echo "$app" |passwd $u --stdin
## Disable local login, so access is exclusively by SSH tunnel with key-based AuthN.
passwd -l $u

# Allow $subject to read files of $u 
#groups $subject |grep $u || usermod -aG $u $subject 
#chmod 770 $d

## Verify that $u is provisioned
restorecon -Rv $alt/home # Apply any resulting SELinux fcontext changes (again, just to be sure).
seVerify || {
    echo " ERR : FAILed @ SELinux : semanage fcontext"

    exit 66
}
ls -ZRhl $alt
grep $u /etc/subuid && grep $u /etc/subgid || {
    echo "  ERR : FAILed @ subids"

    exit 77
}

#sudo su $u podman system migrate

## Podman rootless scheme requires an active, full-loaded user session.
## Start an SSH login session : Locally via the loopback interface:
## - Starts per-user systemd session
## - XDG_RUNTIME_DIR, /run/user/<UID>, is created
## - DBus Session Bus is spawned
## This allows for cryptographically-secured (key-based/passwordless) AuthN.
##
## 1. Provision $subject (once) for SSH key-based AuthN against $u.
key="/home/$subject/.ssh/$app"
[[ -f $key ]] ||
    ssh-keygen -t ecdsa -b 521 -C "$subject@$(hostname)" -N '' -f $key
pub="$(cat $key.pub)" || {
    echo "  ERR : Public-key file is missing or empty : See '$key'"

    exit 88
}
uhome="$alt/home/$subject"
auth=$uhome/.ssh/authorized_keys
[[ $(grep "$pub" $auth) ]] || {
    mkdir -p $uhome/.ssh
    chmod 0700 $uhome/.ssh
    echo "$pub" |tee -a $auth
    chmod 0600 $auth
    chown -R $u:$u $uhome/.ssh
}
## 2. Verify rootless Podman config and AuthN/AuthZ elsewise for $subject via local SSH tunnel as $u.
#type -t yq && ssh -i $key $u@localhost podman info |yq .store |yq ' . | {"store": { "configFile": .configFile,"graphRoot":.graphRoot, "volumePath": .volumePath}}'
ssh -i $key $u@localhost whoami &&
    loginctl user-status $u |grep -e State: -e Linger: &&
        ssh -i $key $u@localhost podman network ls &&
            ssh -i $key $u@localhost podman version  &&
                echo -e '\nok'

