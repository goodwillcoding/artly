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
# get the automake libdire so we can use mkinstalldirs
AUTOMAKE_LIBDIR=$(shell automake --print-libdir)


# ........................................................................... #
# program name
NAME = artly
# package name
PACKAGE_NAME = $(NAME)
# program and package version
VERSION := $(shell ./src/artly --version --machine-readable | grep "^artly-version:" | cut -d':' -f2)
PACKAGE_NAME_FULL = $(PACKAGE_NAME)-$(VERSION)


# ........................................................................... #
# code revision
REVISION := $(shell git rev-parse --short HEAD || echo unknown)
# code branch
BRANCH := $(shell git show-ref | grep "$(REVISION)" | grep -v HEAD | awk '{print $$2}' | sed 's|refs/remotes/origin/||' | sed 's|refs/heads/||' | sort | head -n 1 || echo unknown)
# latest stable tag
LATEST_STABLE_TAG := $(shell git tag -l "*.*.*" --sort=-v:refname | head -n 1 || echo unknown)


# ........................................................................... #
ARTLY_LIBDIR=$(DESTDIR)$(libdir)/artly
# build date
BUILD_DATE := $(shell date +"%Y-%m-%d %R %Z %z")
# build folder
BUILD_FOLDER = $(CURDIR)/build
# output folder
OUTPUT_FOLDER = $(CURDIR)/output
# source archive created by dist
SOURCE_ARCHIVE_FILE = $(OUTPUT_FOLDER)/$(PACKAGE_NAME)_$(VERSION).tar.gz

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
clean: ;

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
	$(AUTOMAKE_LIBDIR)/mkinstalldirs \
	  $(DESTDIR)$(bindir) \
	  $(DESTDIR)$(libdir)

	@# create lib/artly
	$(AUTOMAKE_LIBDIR)/mkinstalldirs \
	  $(ARTLY_LIBDIR)

	@# create lib/artly/core
	$(AUTOMAKE_LIBDIR)/mkinstalldirs \
	  -m 0755 \
	  $(ARTLY_LIBDIR)/core

	@# create lib/artly/core/_static
	$(AUTOMAKE_LIBDIR)/mkinstalldirs \
	  -m 0755 \
	  $(ARTLY_LIBDIR)/core/_static

	@# create lib/artly/core/_static/css
	$(AUTOMAKE_LIBDIR)/mkinstalldirs \
	  -m 0755 \
	  $(ARTLY_LIBDIR)/core/_static/css

	@# create lib/artly/core/_static/fonts
	$(AUTOMAKE_LIBDIR)/mkinstalldirs \
	  -m 0755 \
	  $(ARTLY_LIBDIR)/core/_static/fonts


# ........................................................................... #
install: installdirs

	@# install artly core scripts
	install \
	  --mode 755 \
	  src/core/artly-*.sh \
	  $(ARTLY_LIBDIR)/core

	@# install artly utils library
	install \
	  --mode 644 \
	  src/core/utils.sh \
	  $(ARTLY_LIBDIR)/core

	@# install artly top level wrapper script
	install \
	  --mode 755 \
	  src/artly \
	  $(ARTLY_LIBDIR)

	@# create artly top wrapper bindir to libdir RELATIVE symlink
	@# (basically: /usr/bin/artly -> ../lib/artly/artly)
	ln \
	  --force \
	  --symbolic \
	  --relative \
	  $(ARTLY_LIBDIR)/artly \
	  $(DESTDIR)$(bindir)/artly

	@# install artly _static css assets
	install \
	  --mode 644 \
	  src/core/_static/css/* \
	  $(ARTLY_LIBDIR)/core/_static/css

	@# install artly _static font  assets
	install \
	  --mode 644 \
	  src/core/_static/fonts/* \
	  $(ARTLY_LIBDIR)/core/_static/fonts

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
dist:

	@# make output folder
	mkdir \
		--parents \
		$(OUTPUT_FOLDER);

	@# create the source archive
	tar \
		--create \
		--gzip \
		--preserve-permissions \
		--owner 0 \
		--group 0 \
		--transform 's|^|$(PACKAGE_NAME_FULL)/|' \
		--file "$(SOURCE_ARCHIVE_FILE)" \
		--directory "$(CURDIR)" \
		Makefile \
		README.rst \
		LICENSE.rst \
		CHANGES.rst \
		DISCLAIMER.rst \
		src/


# ........................................................................... #
distclean: clean


# ........................................................................... #
package-dependencies: build-deps
	sudo apt-get install debhelper devscripts


# ........................................................................... #
ubuntu-xenial-packages: dist

	mkdir \
	  --parents \
	  $(BUILD_FOLDER)/ubuntu/xenial

	cp \
	  $(SOURCE_ARCHIVE_FILE) \
	  $(BUILD_FOLDER)/ubuntu/xenial


# ........................................................................... #
publish: ;

# ........................................................................... #
.PHONY: all install clean distclean uninstall
