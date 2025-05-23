#!/usr/bin/env bash
###########################################################################
# Provision a stable rootless Podman environment for an AD user
# by creating a locked local user account for AD user to run as,
# only by key-based AuthN in an SSH tunnel.
#
# ARGs: [DOMAIN_USER] (Default is SUDO_USER)
#
# - Idempotent
###########################################################################

## Guardrails
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

grep -e "^$domain_user" /etc/passwd && {
    echo "  This script creates a local account, '$local_user', only for a *non-local* (AD domain) user."
    echo "  However, this user, '$domain_user', is *local*."
    echo "  Local users are advised to run (rootless) Podman from their existing local account."
    
    exit 22
}

seVerify(){
    ## Verify SELinux fcontext equivalence : "/home = $alt/home"
    semanage fcontext --list |grep "$alt" |grep "$alt/home = /home"
}
export -f seVerify

## Create a local user account having a non-standard (alt) HOME which SELinux treats as it would those of /home
##   Attempts to configure a *system* user (-r, --system) for rootless podman fail by many layered modes.
##   Podman expects and relies upon numerous adjacent services and processes,
##   available only to *regular* local user accounts, when provisioning per-user rootless containers.
mkdir -p $alt/home
seVerify || {
    ## Force SELinux to accept SELinux declarations REGARDLESS of current state of SELinux objects at target(s)
    semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null # Delete all rules; is okay if no rules exist.
    restorecon -Rv $alt/home # Apply the above purge (now).
    ## Declare SELinux fcontext equivalence : "/home = $alt/home"
    semanage fcontext --add --equal /home $alt/home 
    restorecon -Rv $alt/home # Apply the above rule (now).
}

## Create user and group for use as local account for $domain_user
id -un $local_user >/dev/null 2>&1 || {
    useradd --create-home --home-dir $alt_home --shell /bin/bash $local_user
    loginctl enable-linger $local_user
}
#usermod -s /bin/bash $local_user
echo "$app" |passwd $local_user --stdin
## Disable local login, so AuthN/AuthZ is exclusively by SSH key/tunnel.
passwd -l $local_user

# Allow $domain_user to read files of $local_user 
#groups $domain_user |grep $local_group || usermod -aG $local_group $domain_user 
#chmod 770 $alt_home

## Verify that $local_user is provisioned
restorecon -Rv $alt/home # Apply any resulting SELinux fcontext changes (again, just to be sure).
ls -ZRhl $alt
seVerify || {
    echo " ERR : FAILed @ SELinux : semanage fcontext"

    exit 66
}
grep $local_user /etc/subuid && grep $local_group /etc/subgid || {
    echo "  ERR : FAILed @ subids"

    exit 77
}

#sudo su $local_user podman system migrate

## Podman rootless scheme requires an active, full-loaded user session.
## Start an SSH login session : Locally via the loopback interface:
## - Starts per-user systemd session
## - XDG_RUNTIME_DIR, /run/user/<UID>, is created
## - DBus Session Bus is spawned
## This allows key-based passwordless AuthN.
##
## 1. Provision $domain_user (once) for SSH key-based AuthN against $local_user.
key="/home/$domain_user/.ssh/$app"
[[ -f $key ]] ||
    ssh-keygen -t ecdsa -b 521 -C "$domain_user@$(hostname)" -N '' -f $key
pub="$(cat $key.pub)" || {
    echo "  ERR : Public-key file is missing or empty : See '$key'"

    exit 88
}
localhome="$alt/home/$domain_user"
auth=$localhome/.ssh/authorized_keys
[[ $(grep "$pub" $auth) ]] || {
    mkdir -p $localhome/.ssh
    chmod 0700 $localhome/.ssh
    echo "$pub" |tee -a $auth
    chmod 0600 $auth
    chown -R $local_user:$local_user $localhome/.ssh
}
## 2. Verify rootless Podman config and AuthN/AuthZ elsewise for $domain_user via local SSH tunnel as $local_user.
#type -t yq && ssh -i $key $local_user@localhost podman info |yq .store |yq ' . | {"store": { "configFile": .configFile,"graphRoot":.graphRoot, "volumePath": .volumePath}}'
ssh -i $key $local_user@localhost whoami &&
    loginctl user-status $local_user |grep -e State: -e Linger: &&
        ssh -i $key $local_user@localhost podman network ls &&
            ssh -i $key $local_user@localhost podman version  &&
                echo -e '\nok'

