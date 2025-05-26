#!/usr/bin/env bash
######################################################################
# DO NOT MODIFY : ARTIFACT of 'podman-provision-user.sh.tpl' @ 4e5c98d
######################################################################
app=podman
admins=ad-linux-sudoers
app_sudoers=ad-linux-users
img=alpine
[[ -n "${SUDO_USER:-}" ]] || {
    echo "⚠  USAGE: sudo ${BASH_SOURCE##*/}" >&2
    echo "   REQUIREs membership in GROUP: '$app_sudoers'" >&2
    exit 1
}
groups "${SUDO_USER:-}" |grep "$app_sudoers" || {
    echo "⚠  This script REQUIREs membership in GROUP: '$app_sudoers'" >&2
    exit 2
}
domain_user=$SUDO_USER
[[ $1 ]] && groups $SUDO_USER |grep "$admins" && domain_user=$1
alt=/work/$app
alt_home=$alt/home/$domain_user
local_user=$app-$domain_user
local_group=$local_user
id "$local_user" >/dev/null 2>&1 && grep -qe "^$local_user" /etc/passwd && {
    echo "⚠  Local user '$local_user' already exists." >&2
    exit 11
}
logger "Script run by '$SUDO_USER' via sudo : '$BASH_SOURCE'"
grep -qe "^$domain_user" /etc/passwd && {
    echo "⚠  This script creates a local-proxy account, '$app-$domain_user', for an external (AD) user." >&2
    echo "    However, this user ($domain_user) is *local*." >&2
    echo "    Local users are advised to run $app from their existing local account." >&2
    exit 22
}
seVerify(){
    semanage fcontext --list |grep "$alt" |grep "$alt/home = /home"
}
export -f seVerify
mkdir -p $alt/home
seVerify || {
    semanage fcontext --delete "$alt/home(/.*)?" 2>/dev/null
    restorecon -Rv $alt/home
    semanage fcontext --add --equal /home $alt/home
    restorecon -Rv $alt/home
}
id "$local_user" >/dev/null 2>&1 || {
    useradd --create-home --home-dir $alt_home --shell /sbin/nologin $local_user
    loginctl enable-linger "$local_user"
}
id "$local_user" >/dev/null 2>&1 || {
    echo "⚠  ERR : FAILed @ useradd : '$local_user' does NOT EXIST." >&2
    exit 33
}
groups "$domain_user" |grep "$app_sudoers" || {
    usermod -aG "$app_sudoers" "$domain_user" &&
        echo "🚧  User '$domain_user' may need to LOGOUT/LOGIN to activate their membership in group '$app_sudoers'." >&2
}
groups "$domain_user" |grep "$local_group" || {
    usermod -aG "$local_group" "$domain_user" &&
        echo "🚧  User '$domain_user' may need to LOGOUT/LOGIN to activate their membership in group: '$local_group'." >&2
}
chown -R $local_user:$local_group $alt_home
find $alt_home -type d -exec chmod 775 {} \+
find $alt_home -type f -exec chmod 660 {} \+
restorecon -Rv $alt/home
ls -Zhld $alt_home
seVerify || {
    echo "⚠  ERR : FAILed @ SELinux : semanage fcontext" >&2
    exit 66
}
grep -q $local_user /etc/subuid || {
    echo "⚠  ERR : FAILed to add subUID range for local-proxy user '$local_user'" >&2
    exit 77
}
grep -q $local_group /etc/subgid || {
    echo "⚠  ERR : FAILed to add subGID range for local-proxy group '$local_group'" >&2
    exit 78
}
echo -e "\n✅  Provision complete.\n"
echo -e "📦  Verify by running a container using podman via its transparent wrapper, which handles your local-proxy configuration:"
su "$domain_user" -c "/usr/local/bin/podman-test.sh $alt_home $img"
exit $? 
