#!/usr/bin/make -f

# ########################################################################### #
#
# Building, Packaging and Publishing Setup for Artly
#
# Prerequisites
#  - make
#  - coreutils
#  - grep
#  - awk
#  - sed
#  - git
#  - automake
#
# ########################################################################### #

# ........................................................................... #
# set explicit shell
SHELL = /usr/bin/env bash


# ........................................................................... #
# https://www.gnu.org/prep/standards/html_node/Directory-Variables.html#Directory-Variables
# GNU style defaul install prefix
prefix = /usr/local
# GNU style defaul install exec_prefix
exec_prefix = $(prefix)
# GNU style defaul bindir
bindir = $(exec_prefix)/bin
# GNU style defaul libdir
libdir = $(exec_prefix)/lib

# build support folder
BUILD_SUPPORT = $(CURDIR)/build-support
BUILD_SUPPORT_BIN = $(BUILD_SUPPORT)/bin


# ........................................................................... #
# program name
NAME = artly
# package name
PACKAGE_NAME = $(NAME)
# program and package version
VERSION := $(shell ./src/artly --version --machine-readable | grep "^artly-version:" | cut -d':' -f2)


# ........................................................................... #
# code revision
REVISION := $(shell git rev-parse --short HEAD || echo unknown)
# code branch
BRANCH := $(shell git show-ref | grep "$(REVISION)" | grep -v HEAD | awk '{print $$2}' | sed 's|refs/remotes/origin/||' | sed 's|refs/heads/||' | sort | head -n 1 || echo unknown)
# latest stable tag
LATEST_STABLE_TAG := $(shell git tag -l "*.*.*" --sort=-v:refname | head -n 1 || echo unknown)


# ........................................................................... #
# destination
ARTLY_INSTALLATION_LIBDIR = $(DESTDIR)$(libdir)/artly
# build date
BUILD_DATE := $(shell date +"%Y-%m-%d %R %Z %z")
# build folder
BUILD_FOLDER = $(CURDIR)/_build
# output folder
OUTPUT_FOLDER = $(CURDIR)/_output
# source archive created by dist
SOURCE_ARCHIVE_FILE = $(OUTPUT_FOLDER)/source/$(PACKAGE_NAME)-$(VERSION).tar.gz


# ........................................................................... #
all: ;


# ........................................................................... #
help:
	# Commands:
	# make all - ???
	# make about - show information about package (name, version, git info)
	#
	# Development commands:
	# make install - install program into DESTDIR
	# make clean - remove program from DESTDIR
	#
	# Packaging commands
	# make packaging-dependencies - install packaging dependencies
	# make ubuntu-xenial-packages - build packages for debian
	#
	# Deployment commands:
	# make publish - publish packages


# ........................................................................... #
about:

	@echo "NAME               : $(NAME)";
	@echo "VERSION            : $(VERSION)";
	@echo "PACKAGE NAME       : $(PACKAGE_NAME)";
	@echo "REVISION           : $(REVISION)";
	@echo "BRANCH             : $(BRANCH)";
	@echo "LATEST STABLE TAG  : $(LATEST_STABLE_TAG)";
	@echo "BUILD DATE         : $(BUILD_DATE)"


# ........................................................................... #
clean: distclean clean-ubuntu-xenial-packages

	@# remove build folder
	-rm \
	  --recursive \
	  --force \
	  $(BUILD_FOLDER)

	@# remove output folder
	-rm \
	  --recursive \
	  --force \
	  $(OUTPUT_FOLDER)


# ........................................................................... #
# Make sure all installation directories (e.g. $(bindir))
# actually exist by making them if necessary.
installdirs:

	@# ensure bin and lib dirs are in place
	$(BUILD_SUPPORT_BIN)/mkinstalldirs \
	  $(DESTDIR)$(bindir) \
	  $(DESTDIR)$(libdir)

	@# create lib/artly
	$(BUILD_SUPPORT_BIN)/mkinstalldirs \
	  $(ARTLY_INSTALLATION_LIBDIR)

	@# create lib/artly/core
	$(BUILD_SUPPORT_BIN)/mkinstalldirs \
	  -m 0755 \
	  $(ARTLY_INSTALLATION_LIBDIR)/core

	@# create lib/artly/core/_static
	$(BUILD_SUPPORT_BIN)/mkinstalldirs \
	  -m 0755 \
	  $(ARTLY_INSTALLATION_LIBDIR)/core/_static

	@# create lib/artly/core/_static/css
	$(BUILD_SUPPORT_BIN)/mkinstalldirs \
	  -m 0755 \
	  $(ARTLY_INSTALLATION_LIBDIR)/core/_static/css

	@# create lib/artly/core/_static/fonts
	$(BUILD_SUPPORT_BIN)/mkinstalldirs \
	  -m 0755 \
	  $(ARTLY_INSTALLATION_LIBDIR)/core/_static/fonts


# ........................................................................... #
install: installdirs

	@# install artly core scripts
	install \
	  --mode 755 \
	  src/core/artly-*.sh \
	  $(ARTLY_INSTALLATION_LIBDIR)/core

	@# install artly utils library
	install \
	  --mode 644 \
	  src/core/utils.sh \
	  $(ARTLY_INSTALLATION_LIBDIR)/core

	@# install artly top level wrapper script
	install \
	  --mode 755 \
	  src/artly \
	  $(ARTLY_INSTALLATION_LIBDIR)

	@# create artly top wrapper bindir to libdir RELATIVE symlink
	@# (basically: /usr/bin/artly -> ../lib/artly/artly)
	ln \
	  --force \
	  --symbolic \
	  --relative \
	  $(ARTLY_INSTALLATION_LIBDIR)/artly \
	  $(DESTDIR)$(bindir)/artly

	@# install artly _static css assets
	install \
	  --mode 644 \
	  src/core/_static/css/* \
	  $(ARTLY_INSTALLATION_LIBDIR)/core/_static/css

	@# install artly _static font  assets
	install \
	  --mode 644 \
	  src/core/_static/fonts/* \
	  $(ARTLY_INSTALLATION_LIBDIR)/core/_static/fonts

# ........................................................................... #
uninstall:

	@# remove the artly bin/ symlink
	-rm \
		--force \
		$(DESTDIR)$(prefix)/bin/artly

	@# remove the artly lib/ folder
	-rm \
		--force \
		--recursive \
		$(DESTDIR)$(prefix)/lib/artly


# ........................................................................... #
dist: distclean

	@# make source output folder
	mkdir \
		--parents \
		$(OUTPUT_FOLDER)/source;


	@# create the source archive, preserving permissions and setting owner and
	@# group to root. In the tarball source code goes into the folder of
	@# name-version
	tar \
		--create \
		--gzip \
		--preserve-permissions \
		--owner 0 \
		--group 0 \
		--transform 's|^|$(PACKAGE_NAME)-$(VERSION)/|' \
		--file "$(SOURCE_ARCHIVE_FILE)" \
		--directory "$(CURDIR)" \
		Makefile \
		README.rst \
		LICENSE.rst \
		CHANGES.rst \
		DISCLAIMER.rst \
		build-support/bin/ \
		src/


# ........................................................................... #
distclean:

	@# remove output folder
	-rm \
	  --recursive \
	  --force \
	  $(OUTPUT_FOLDER)/source


# ........................................................................... #
print-debian-build-dependencies:

	@echo build-essential devscripts debhelper debmake gnupg2


# ........................................................................... #
ubuntu-xenial-packages: | clean-ubuntu-xenial-packages dist

	@# create the ubuntu/xenial build folder
	mkdir \
	  --parents \
	  $(BUILD_FOLDER)/ubuntu/xenial

	@# copy the source distribution to build folder of ubuntu/xenial
	cp \
	  $(SOURCE_ARCHIVE_FILE) \
	  $(BUILD_FOLDER)/ubuntu/xenial/$(PACKAGE_NAME)_$(VERSION).orig.tar.gz

	@# extract the source archive into build folder of ubuntu/xenial
	tar \
	  --extract \
	  --gzip \
	  --touch \
	  --file $(SOURCE_ARCHIVE_FILE) \
	  --directory $(BUILD_FOLDER)/ubuntu/xenial

	@# copy the debian/ configuration folder into the extracted folder
	@# (it was created with name-version format)
	cp \
	  --recursive \
	  $(BUILD_SUPPORT)/ubuntu/xenial/debian \
	  $(BUILD_FOLDER)/ubuntu/xenial/$(PACKAGE_NAME)-$(VERSION)

	@# build the the package
	(\
		cd $(BUILD_FOLDER)/ubuntu/xenial/$(PACKAGE_NAME)-$(VERSION); \
		debuild \
		  -pgpg2 \
		  -k$(SIGNERS_GPG_KEYID); \
	)

	@# create the ubuntu/xenial build folder
	mkdir \
	  --parents \
	  $(OUTPUT_FOLDER)/ubuntu/xenial

	@# copy the over debian source, and binary distributions as well as the
	@# changes file to the output file
	install \
	  --mode 644 \
	  $(BUILD_FOLDER)/ubuntu/xenial/$(PACKAGE_NAME)_$(VERSION)*.tar.xz \
	  $(BUILD_FOLDER)/ubuntu/xenial/$(PACKAGE_NAME)_$(VERSION)*.dsc \
	  $(BUILD_FOLDER)/ubuntu/xenial/$(PACKAGE_NAME)_$(VERSION)*.orig.tar.gz \
	  $(BUILD_FOLDER)/ubuntu/xenial/$(PACKAGE_NAME)_$(VERSION)*.deb \
	  $(BUILD_FOLDER)/ubuntu/xenial/$(PACKAGE_NAME)_$(VERSION)*.changes \
	  $(OUTPUT_FOLDER)/ubuntu/xenial


# ........................................................................... #
clean-ubuntu-xenial-packages:

	@# remove the build folder
	@# use --force for when ubuntu/xenial does not exist
	-rm \
	  --recursive \
	  --force \
	  $(BUILD_FOLDER)/ubuntu/xenial

	@# remove the build folder
	@# use --force for when ubuntu/xenial does not exist
	-rm \
	  --recursive \
	  --force \
	  $(OUTPUT_FOLDER)/ubuntu/xenial


# ........................................................................... #
publish: ;

# ........................................................................... #
.PHONY: all install clean distclean uninstall
