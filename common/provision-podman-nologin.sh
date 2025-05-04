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
    useradd --create-home --home-dir $d --shell /sbin/nologin $u
    loginctl enable-linger $u
}
#usermod -s /bin/bash $u
#echo "$u" |sudo passwd $u --stdin
#restorecon -Rv $alt/home

sudoers=/etc/sudoers.d/$u
[[ -f $sudoers ]] || tee $sudoers <<EOH
%$u ALL=($u) NOPASSWD: /usr/bin/podman *
EOH

usermod -aG $u $SUDO_USER

## Verify
seVerify || echo FAILed @ SELinux : semanage fcontext
ls -ZRhl $alt
grep $u /etc/subuid
grep $u /etc/subgid

## Create sudo user's working directory
wdir="$alt/podman-users/$SUDO_USER"
mkdir -p $wdir
chown -R $SUDO_USER:$u $wdir

#sudo su $u podman system migrate

pushd $wdir &&
    sudo -u $u podman info |sudo -u $u podman tee podman.info.yaml &&
        popd

#sudo -u $u podman run busybox sh -c 'echo === Hello from container $(hostname -f)'

