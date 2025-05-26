#!/usr/bin/env bash
####################################################################
# Process a template into its bash script
#
# - Idempotent
####################################################################
set -euo pipefail

src=per-user
tmp=tmp

header(){
	cat <<-EOH
	#!/usr/bin/env bash
	######################################################################
	# DO NOT MODIFY : ARTIFACT of '$1.tpl'
	######################################################################
	EOH
}
tpl2sh(){
    [[ -r $src/$1.tpl ]] || return 1
    cat $src/$1.tpl \
        |sed "s,APP_NAME,${APP_NAME},g" \
        |sed "s,APP_PROVISION_USER,${APP_PROVISION_USER},g" \
        |sed "s,APP_OCI_TEST_IMAGE,${APP_OCI_TEST_IMAGE},g" \
        |sed "s,SYS_GROUP_ADMINS,${SYS_GROUP_ADMINS},g" \
        |sed "s,SYS_GROUP_DOMAIN_USERS,${SYS_GROUP_DOMAIN_USERS},g" \
        |sed "s,SYS_GROUP_LOCAL_PROXY,${SYS_GROUP_LOCAL_PROXY},g" \
        |sed -E '/^[[:space:]]*#/d; s/[[:space:]]+#.*$//' \
        |sed '/^[[:space:]]*$/d' \
        |tee $tmp

    header $1 |cat - $tmp |tee $src/$1
    rm $tmp
}

"$@" || echo ERR : $?

exit $?
#######
