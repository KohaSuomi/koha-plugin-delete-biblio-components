
SHELL := /bin/bash

PLUGINPM := "DeleteBiblioComponents.pm"
PLUGINNAME := "delete-biblio-components"

PLUGINFILE := $(shell find Koha/Plugin/ -iname $(PLUGINPM) | head -1)
PLUGINVER := `grep "^ *version *=" "$(PLUGINFILE)" | head -1 | cut -d"'" -f 2`
RELEASE_FILE = "koha-plugin-$(PLUGINNAME)-v$(PLUGINVER).kpz"

test:
	@if [[ -z "$(PLUGINFILE)" ]]; then echo "ERROR: $$PLUGINFILE PLUGIN FILE cannot be found."; exit 1; fi
	@if [[ -z "$(PLUGINNAME)" ]]; then echo "ERROR: PLUGIN NAME cannot be found."; exit 1; fi
	@if [[ -z "$(PLUGINVER)" ]]; then echo "ERROR: PLUGIN VERSION cannot be found."; exit 1; fi
	@echo "Name: $(PLUGINNAME), version: $(PLUGINVER), OK"

all: test spotless plugin

plugin: test spotless
	@zip -r "$(RELEASE_FILE)"  Koha/

spotless: test
	@rm -f koha-plugin-$(PLUGINNAME)-v*.kpz
	@rm -f `find . -name \*~`
