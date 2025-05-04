#!/usr/bin/env bash
####################################################################
# Provision a stable rootless Podman environment for an AD user
# by creating a local service account (--shell /sbin/nologin),
# under which the otherwise unprivileged namesake (AD user)
# may sudo only the set of commands declared at a sudoers file
# scoped to AD user's group "podman-sudoers".
#
# - Idempotent
####################################################################

## Guardrails
[[ $(whoami) == 'root' ]] || { 
    echo '  Must RUN AS root'
    
    exit 11
}
logger "Script run by $SUDO_USER via sudo : $BASH_SOURCE"

subject=$SUDO_USER
## Allow admins to select the subject AD user
[[ $1 ]] && groups $SUDO_USER |grep ad-linux-sudoers && subject=$1

app=podman
alt=/work/$app
d=$alt/home/$subject
u=$app-$subject
g=$u

grep -e "^$subject" /etc/passwd && {
    echo "  This script provisions a local account, '$app-$subject', for a *non-local* (AD) user."
    echo "  However, this subject user, '$subject', is *local*. (See /etc/passwd)"
    echo "  Local users are advised to run (rootless) Podman from their existing local account."

    exit 22
}

## Create a local user account having a non-standard (alt) HOME which SELinux treats as it would those of /home
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

## Create a *regular* user (and group), having no login shell, for use as the service account.
## Podman rootless requires an active login shell (DBus Session Bus, etc.), so fail if --system user.
id -un $u >/dev/null 2>&1 || {
    useradd --create-home --home-dir $d --shell /sbin/nologin $u
    loginctl enable-linger $u
}
ps=podman-sudoers
groups $subject |grep $ps || usermod -aG $ps $subject

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

seVerify || echo FAILed @ SELinux : semanage fcontext
ls -ZRhl $alt
grep $u /etc/subuid
grep $u /etc/subgid

## Create "neutral" working directory
## - Not HOME of $u         : $subject fails AuthZ
## - Not HOME of $subject   : $u fails AuthZ
wdir="$alt/scratch/$subject"
mkdir -p $wdir
chown -R $subject:$u $wdir
chmod 755 $wdir

#sudo su $u podman system migrate

pushd $wdir &&
    sudo -u $u /usr/bin/podman info |tee podman.info.yaml &&
        popd

#sudo -u $u podman run busybox sh -c 'echo === Hello from container $(hostname -f)'

