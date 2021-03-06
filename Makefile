#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2019, Joyent, Inc.
#

#
# Makefile: basic Makefile for template API service
#
# This Makefile is a template for new repos. It contains only repo-specific
# logic and uses included makefiles to supply common targets (javascriptlint,
# jsstyle, restdown, etc.), which are used by other repos as well. You may well
# need to rewrite most of this file, but you shouldn't need to touch the
# included makefiles.
#
# If you find yourself adding support for new targets that could be useful for
# other projects too, you should add these to the original versions of the
# included Makefiles (in eng.git) so that other teams can use them too.
#

#
# Tools
#
BASHSTYLE	 = $(NODE) tools/bashstyle
TAPE		:= ./node_modules/.bin/tape
NPM		:= npm
NGXSYMCHECK	= tools/ngx_symcheck

#
# Files
#
DOC_FILES	=
BASH_FILES	= bin/manta-mako-adm $(NGXSYMCHECK)
JS_FILES	:= $(shell find lib test bin -name '*.js')
JSL_CONF_NODE	= tools/jsl.node.conf
JSL_FILES_NODE	= $(JS_FILES)
JSSTYLE_FILES	= $(JS_FILES)
JSSTYLE_FLAGS	= -f tools/jsstyle.conf

#
# Variables
#
NAME			= mako
NODE_PREBUILT_VERSION	= v0.10.48
NODE_PREBUILT_TAG	= zone
# minimal-multiarch 18.1.0
NODE_PREBUILT_IMAGE	= 1ad363ec-3b83-11e8-8521-2f68a4a34d5d

#
# Stuff used for buildimage
#
BASE_IMAGE_UUID		= b6ea7cb4-6b90-48c0-99e7-1d34c2895248
BUILDIMAGE_NAME		= manta-storage
BUILDIMAGE_DESC		= Manta Storage
BUILDIMAGE_PKGSRC	= pcre-8.42 findutils-4.6.0nb1 gawk-4.1.4nb1
AGENTS = amon config minnow registrar

ENGBLD_USE_BUILDIMAGE	= true
ENGBLD_REQUIRE :=	$(shell git submodule update --init deps/eng)
include ./deps/eng/tools/mk/Makefile.defs
TOP ?= $(error Unable to access eng.git submodule Makefiles.)

ifeq ($(shell uname -s),SunOS)
	include ./deps/eng/tools/mk/Makefile.node_prebuilt.defs
	include ./deps/eng/tools/mk/Makefile.agent_prebuilt.defs
else
	include ./deps/eng/tools/mk/Makefile.node.defs
endif
include ./tools/mk/Makefile.nginx.defs

#
# MG Variables
#
ROOT            := $(shell pwd)
RELEASE_TARBALL := $(NAME)-pkg-$(STAMP).tar.bz2
RELSTAGEDIR		:= /tmp/$(NAME)-$(STAMP)

#
# v8plus uses the CTF tools as part of its build, but they can safely be
# overridden here so that this works in dev zones without them.
# See marlin.git Makefile.
#
NPM_ENV          = MAKE_OVERRIDES="CTFCONVERT=/bin/true CTFMERGE=/bin/true"

#
# Repo-specific targets
#
.PHONY: all
all: $(NODE_EXEC) $(NGINX_EXEC) $(TAPE) $(REPO_DEPS) scripts
	$(NPM) install
$(TAPE): | $(NPM_EXEC)
	$(NPM) install

CLEAN_FILES += $(TAPE) ./node_modules/ build

check-bash: $(NODE_EXEC)

.PHONY: test
test: $(TAPE)
	@for f in test/*.test.js; do	\
		echo "# $$f";	\
		$(TAPE) $$f || exit 1; \
	done

.PHONY: scripts
scripts: deps/manta-scripts/.git
	mkdir -p $(BUILD)/scripts
	cp deps/manta-scripts/*.sh $(BUILD)/scripts

.PHONY: check-nginx
check-nginx: $(NGINX_EXEC)
	$(NGXSYMCHECK) $(NGINX_EXEC)
prepush: check-nginx

#
# The eng.git makefiles define the clean target using a :: rule. This
# means that we're allowed to have multiple bodies that define the rule
# and they should all take effect. We ignore the return value from the
# recursive make clean because there is no guarantee that there's a
# generated Makefile or that the nginx submodule has been initialized
# and checked out.
#
clean::
	-(cd deps/nginx && $(MAKE) clean)

.PHONY: release
release: all deps docs $(SMF_MANIFESTS) check-nginx
	@echo "Building $(RELEASE_TARBALL)"
	@mkdir -p $(RELSTAGEDIR)/root/opt/smartdc/mako
	@mkdir -p $(RELSTAGEDIR)/root/opt/smartdc/boot
	@mkdir -p $(RELSTAGEDIR)/site
	@touch $(RELSTAGEDIR)/site/.do-not-delete-me
	cp -r $(ROOT)/bin \
	    $(ROOT)/boot \
	    $(ROOT)/build \
	    $(ROOT)/build/nginx \
	    $(ROOT)/lib \
	    $(ROOT)/node_modules \
	    $(ROOT)/sapi_manifests \
	    $(ROOT)/smf \
	    $(RELSTAGEDIR)/root/opt/smartdc/mako/
	cp -r $(ROOT)/build/scripts $(RELSTAGEDIR)/root/opt/smartdc/mako/boot
	ln -s /opt/smartdc/mako/boot/setup.sh \
	    $(RELSTAGEDIR)/root/opt/smartdc/boot/setup.sh
	chmod 755 $(RELSTAGEDIR)/root/opt/smartdc/mako/boot/setup.sh
	rm $(RELSTAGEDIR)/root/opt/smartdc/mako/nginx/conf/*.default
	(cd $(RELSTAGEDIR) && $(TAR) -jcf $(ROOT)/$(RELEASE_TARBALL) root site)
	@rm -rf $(RELSTAGEDIR)

.PHONY: publish
publish: release
	mkdir -p $(ENGBLD_BITS_DIR)/$(NAME)
	cp $(ROOT)/$(RELEASE_TARBALL) $(ENGBLD_BITS_DIR)/$(NAME)/$(RELEASE_TARBALL)

include ./deps/eng/tools/mk/Makefile.deps
ifeq ($(shell uname -s),SunOS)
	include ./deps/eng/tools/mk/Makefile.node_prebuilt.targ
	include ./deps/eng/tools/mk/Makefile.agent_prebuilt.targ
else
	include ./deps/eng/tools/mk/Makefile.node.targ
endif
include ./tools/mk/Makefile.nginx.targ
include ./deps/eng/tools/mk/Makefile.targ
