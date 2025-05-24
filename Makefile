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

export APP_NAME                := podman
export APP_GROUP_ADMINS        := ad-linux-sudoers
export APP_GROUP_PROVISIONERS  := ${APP_NAME}-provisioners
export APP_GROUP_LOCAL_PROXY   := ${APP_NAME}-local
export APP_PROVISION_NOLOGIN   := ${APP_NAME}-provision-nologin.sh
export APP_PROVISION_SUDOERS   := ${APP_NAME}-provision-sudoers.sh
export APP_OCI_TEST_IMAGE      := alpine

##############################################################################
## Recipes

## Recipes : Meta
menu :
	$(INFO) 'Install per-user provisioning and usage scripts for Podman rootless mode '
	@echo "install      : Build and install it"
	@echo "commit       : Handle all the Git and FS management"

env:
	$(INFO) 'Environment'
	@echo "PWD=${PRJ_ROOT}"
#	@env |grep K8S_
#	@env |grep ADMIN_

eol :
	find . -type f ! -path '*/.git/*' -exec dos2unix {} \+
mode :
	find . -type d ! -path './.git/*' -exec chmod 0755 "{}" \;
	find . -type f ! -path './.git/*' -exec chmod 0644 "{}" \;
#	find . -type f ! -path './.git/*' -iname '*.sh' -exec chmod 0755 "{}" \;
tree :
	tree -d |tee tree-d
html :
	find . -type f ! -path './.git/*' -name '*.md' -exec md2html.exe "{}" \;
commit push : html tree mode
	gc && git push && gl && gs

## Recipes : App

build:
	bash build.sh
install: build
	sudo -E bash install.sh
teardown:
	sudo -E bash per-user/podman-unprovision-user.sh u0

