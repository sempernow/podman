#!/usr/bin/env bash
alt_home=$1
img=$2

: "${alt_home:?Arg 1 is home dir of local-proxy user}"
: "${img:?Arg 2 is OCI image}"

ok(){
    echo -e "\n✅  Container test complete.\n"
    echo "⚡  Podman ran successfully in rootless mode under your local proxy's namespace ...
    - Pulled an image from an OCI registry: '$img' .
    - Ran its container with a bind mount to your local-proxy user's home directory.
    - Created a file in the container, writing it to the mounted directory (available at the host).
    "
    echo -e "\n🔍  Note file owner and group at *host*, which are both 'root' at *container* (above):"
    echo "=== $(whoami)@$(hostname -f)"
    ls -hl $alt_home
    echo -e '\n🧪  Next, try it yourself ...
home="$(getent passwd "podman-$(id -un)" |cut -d: -f6)"
img='"$img"'
podman run --rm --volume $home:/mnt/home $img sh -c '"'touch /mnt/home/another-test-file;ls -hl /mnt/home'"'
ls -hl $home
    '
}
## Verify that this domain user can run podman as the otherwise-unprivileged local-proxy user via the explicitly-declared wrapper script.
/usr/local/bin/podman run --rm --volume $alt_home:/mnt/home $img sh -c '
    echo "🚀  Hello from container $(hostname -f) running as $(whoami) (container context only) !"
    umask 002
    touch /mnt/home/test-write-access-$(date -u '+%Y-%m-%dT%H.%M.%SZ')
    echo "=== $(whoami)@$(hostname -f)"
    ls -hl /mnt/home
' && ok || echo "⚠  Podman's attempt to run a container in rootless mode (under the local-proxy user's namespace), having a bind-mount, has failed."
