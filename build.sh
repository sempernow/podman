#!/usr/bin/env bash
####################################################################
# Process the template into its bash script
#
# - Idempotent
####################################################################
set -euo pipefail

src=per-user
dst=/usr/local/bin

cat $src/${APP_PROVISION_NOLOGIN}.tpl \
    |sed "s,APP_GROUP_ADMINS,${APP_GROUP_ADMINS},g" \
    |sed "s,APP_NAME,${APP_NAME},g" \
    |sed "s,APP_GROUP_PROVISIONERS,${APP_GROUP_PROVISIONERS},g" \
    |sed "s,APP_GROUP_LOCAL_PROXY,${APP_GROUP_LOCAL_PROXY},g" \
    |sed "s,APP_OCI_TEST_IMAGE,${APP_OCI_TEST_IMAGE},g" \
    |tee $src/${APP_PROVISION_NOLOGIN}

