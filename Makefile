default:
	@echo "make dek:	build a legacy deken-package for the deken-plugin"

plugin_version := $(shell egrep "^if.*::deken::versioncheck" deken-plugin.tcl  | sed -e 's| *].*||' -e 's|.* ||')

dek: deken-plugin-$(plugin_version)--externals.zip

.PHONY: dek deken-plugin
deken-plugin: deken-plugin.tcl README.plugin.txt LICENSE.txt
	rm -rf $@
	mkdir -p $@
	cp $^ $@
	mv $@/README.plugin.txt $@/README.txt

deken-plugin-$(plugin_version)--externals.zip: deken-plugin
	deken package --dekformat=0 --version=$(plugin_version) $^
