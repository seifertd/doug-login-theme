THEME   := btrfs-cow
THEMES  := /usr/share/plymouth/themes
HOOKDIR := /etc/initcpio/install
CONFD   := /etc/mkinitcpio.conf.d
SUDO    := $(if $(filter 0,$(shell id -u)),,sudo)
# CachyOS + Limine rebuilds images (and boot entries) with limine-mkinitcpio.
REBUILD := $(if $(shell command -v limine-mkinitcpio),limine-mkinitcpio,mkinitcpio -P)

.PHONY: build preview install enable disable uninstall clean

build:
	python3 tools/build.py

preview: build
	scripts/preview.sh

# Installs the theme and the initramfs hook. Does not make it the default.
install: build
	$(SUDO) rm -rf $(THEMES)/$(THEME)
	$(SUDO) cp -r build/$(THEME) $(THEMES)/$(THEME)
	$(SUDO) install -Dm644 initcpio/$(THEME)-theme $(HOOKDIR)/$(THEME)-theme
	echo 'HOOKS+=($(THEME)-theme)' | $(SUDO) install -Dm644 /dev/stdin $(CONFD)/20-$(THEME)-theme.conf

# Makes it the boot theme and rebuilds every initramfs.
enable: install
	$(SUDO) plymouth-set-default-theme $(THEME)
	$(SUDO) $(REBUILD)

# Switches back to PREVIOUS (default: owl-multihead) and rebuilds.
disable:
	$(SUDO) plymouth-set-default-theme $(or $(PREVIOUS),owl-multihead)
	$(SUDO) $(REBUILD)

uninstall:
	@test "$$(plymouth-set-default-theme)" != $(THEME) || { echo "run 'make disable' first"; exit 1; }
	$(SUDO) rm -rf $(THEMES)/$(THEME) $(HOOKDIR)/$(THEME)-theme $(CONFD)/20-$(THEME)-theme.conf

clean:
	rm -rf build
