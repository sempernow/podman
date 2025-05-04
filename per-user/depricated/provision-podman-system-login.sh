#!/usr/bin/env bash
##############################################################################
# Provision a local system user for AD user to run rootless podman.
#
# ⚠  System user does not meet requirements of Podman's rootless scheme.
#    Podman expects and relies upon numerous adjacent services and processes,
#    available only to *regular* user accounts,
#    when provisioning per-user rootless containers.
##############################################################################

## Guardrails
[[ $(whoami) == 'root' ]] || { 
    echo '  Must RUN AS root'
    
    exit 11
}

grep "$SUDO_USER" /etc/passwd && {
    echo "  This script provisions a local 'podman-*' account for non-local (AD) users only."
    echo "  However, this user, '$SUDO_USER', is local."
    echo "  Local users are advised to run (rootless) Podman from their existing local account."
    
    exit 22

}
## Create a local user account having a non-standard (alt) HOME which SELinux treats as it would those of /home
app=podman
alt=/work/$app
d=$alt/home/$SUDO_USER
u=$app-${SUDO_USER}
g=$u
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
    #userdel -r -Z $u || userdel -Z $u
}

## Create user and group for use as local service account for $SUDO_USER
id -un $u >/dev/null 2>&1 || {
    useradd --system --create-home --home-dir $d --shell /bin/bash $u
    loginctl enable-linger $u
}
#usermod -s /bin/bash $u
echo "$app" |passwd $u --stdin
## Disable local login, so access is exclusively by SSH tunnel with key-based AuthN.
passwd -l $u

## Verify that $u is provisioned
restorecon -Rv $alt/home # Apply any resulting SELinux fcontext changes (again, just to be sure).
seVerify || echo FAILed @ SELinux : semanage fcontext
ls -ZRhl $alt
grep $u /etc/subuid
grep $u /etc/subgid
loginctl user-status $u 2>/dev/null |command grep Linger

#sudo su $u podman system migrate

## Podman rootless scheme requires an active, full-loaded user session.
## Start an SSH login session : Locally via the loopback interface:
## - Starts per-user systemd session
## - XDG_RUNTIME_DIR, /run/user/<UID>, is created
## - DBus Session Bus is spawned
## This allows for cryptographically-secured (key-based/passwordless) AuthN.
## 1. Provision $SUDO_USER (once) for SSH key-based AuthN against $u.
key="/home/$SUDO_USER/.ssh/$app"
[[ -f $key ]] ||
    ssh-keygen -t ecdsa -b 384 -C "$SUDO_USER@$(hostname)" -N '' -f $key
pub="$(cat $key.pub)" || {
    echo "  ERR : Public-key file is missing or empty : See '$key'"
    exit 55
}
uhome="$alt/home/$SUDO_USER"
auth=$uhome/.ssh/authorized_keys
[[ $(grep "$pub" $auth) ]] || {
    mkdir -p $uhome/.ssh
    chmod 0700 $uhome/.ssh
    echo "$pub" |tee -a $auth
    chmod 0600 $auth
}
## 2. Verify rootless Podman config and AuthN/AuthZ elsewise for $SUDO_USER via local SSH tunnel into $u.
ssh -i $key $u@localhost podman info

