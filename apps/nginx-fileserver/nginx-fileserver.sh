#!/usr/bin/env bash
webroot=/srv/nginx-fileserver
semanage fcontext -a -t container_file_t "$webroot(/.*)?"
restorecon -Rv $webroot
