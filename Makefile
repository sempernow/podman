##############################################################################
## Makefile.settings : Environment Variables for Makefile(s)
#include Makefile.settings
# … ⋮ ︙ • “” ‘’ – — ™ ® © ± ° ¹ ² ³ ¼ ½ ¾ ÷ × € ¢ £ ¤ ¥ ₽ ♻ ⚐ ⚑
# ¦ ¶ § † ‡ ß µ ø Ø ƒ Δ ⚒ ☡ ☈ ☧ ☩ ✚ ☨ ☦ ☓ ♰ ♱ ✖ ☘ 웃 𝐀𝐏𝐏 𝐋𝐀𝐁
# ⚠ ☢ ☣ ☠ ⚡ ☑ ✅ ❌ 🔒 🧩 📊 📈 🔍 📦 🧳 🥇 💡 🚀 🚧 🔚
##############################################################################
## Environment variable rules:
## - Any TRAILING whitespace KILLS its variable value and may break recipes.
## - ESCAPE only that required by the shell (bash).
## - Environment hierarchy:
##   - Makefile environment OVERRIDEs OS environment lest set using `?=`.
##  	  - `FOO ?= bar` is overridden by parent setting; `export FOO=new`.
##  	  - `FOO :=`bar` is NOT overridden by parent setting.
##   - Docker YAML `env_file:` OVERRIDEs OS and Makefile environments.
##   - Docker YAML `environment:` OVERRIDEs YAML `env_file:`.
##   - CMD-inline OVERRIDEs ALL REGARDLESS; `make recipeX FOO=new BAR=new2`.

##############################################################################
## $(INFO) : Usage : `$(INFO) 'What ever'` prints a stylized "@ What ever".
SHELL   := /bin/bash
YELLOW  := "\e[1;33m"
RESTORE := "\e[0m"
INFO    := @bash -c 'printf $(YELLOW);echo "@ $$1";printf $(RESTORE)' MESSAGE

##############################################################################
## Project Meta

export PRJ_ROOT := $(shell pwd)
export LOG_PRE  := make
export UTC      := $(shell date '+%Y-%m-%dT%H.%M.%Z')

##############################################################################
## Application declarations

export APP_COMMIT              := $(shell git show --oneline -s |cut -d' ' -f1)
export APP_NAME                := podman
export APP_PROVISION_USER      := ${APP_NAME}-provision-user.sh
export APP_PROVISION_SUDOERS   := ${APP_NAME}-provision-sudoers.sh
export APP_TEST_USER           ?= u0

export APP_OCI_TEST_IMAGE      ?= alpine

export SYS_GROUP_ADMINS        ?= ad-linux-sudoers
export SYS_GROUP_DOMAIN_USERS  ?= ad-linux-users
export SYS_GROUP_PROXY_USERS   ?= local-proxy-users

##############################################################################
## Recipes

## Recipes : Meta
menu :
	$(INFO) 'Install per-user provisioning and usage scripts for Podman rootless mode '
	@echo "build        : Build the provision script"
	@echo "install      : Build and install provision and podman-wrapper scripts"
	@echo "proxy-list   : List all local-proxy users and groups"
	@echo "proxy-add    : Add APP_TEST_USER (${APP_TEST_USER}) to group ${SYS_GROUP_DOMAIN_USERS}"
	@echo "proxy-del    : Unprovision APP_TEST_USER (${APP_TEST_USER}), deleting the local-proxy user, group, and all artifacts."
	$(INFO) 'Meta '
	@echo "env          : Print the Makefile environment"
	@echo "fs           : File mode, MD to HTML, and such FS management"
	@echo "commit       : Handle all the Git and FS management"

env:
	$(INFO) 'Environment'
	@echo "PWD=${PRJ_ROOT}"
	@env |grep APP_
	@env |grep SYS_
#	@env |grep K8S_
#	@env |grep ADMIN_

eol :
	find . -type f ! -path '*/.git/*' -exec dos2unix {} \+
mode fs : html 
	find . -type d ! -path './.git/*' -exec chmod 0755 "{}" \;
	find . -type f ! -path './.git/*' -exec chmod 0644 "{}" \;
#	find . -type f ! -path './.git/*' -iname '*.sh' -exec chmod 0755 "{}" \;
tree :
	tree -d |tee tree-d
html :
	find . -type f ! -path './.git/*' -name '*.md' -exec md2html.exe "{}" \;
commit push : html mode
	gc && git push && gl && gs

## Recipes : App
build:
	bash build.sh tpl2sh ${APP_PROVISION_USER}
	bash build.sh tpl2sh podman.sh

install: build
	sudo -E bash install.sh

proxy-list:
	$(INFO) "Local-proxy Groups"
	@grep podman /etc/group  || echo None
	$(INFO) "Local-proxy Users"
	@grep podman /etc/passwd || echo None
proxy-add:
	sudo usermod -aG ${SYS_GROUP_DOMAIN_USERS} ${APP_TEST_USER}

proxy-del teardown:
	sudo -E bash per-user/podman-unprovision-user.sh ${APP_TEST_USER}
