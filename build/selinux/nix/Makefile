POLICY_NAME := nix
POLICY_VERSION := 1.0

# Source files
TE_FILE := $(POLICY_NAME).te
FC_FILE := $(POLICY_NAME).fc

# Target files
MOD_FILE := $(POLICY_NAME).mod
PP_FILE := $(POLICY_NAME).pp

# Build rules.
# Context-only module: no new types, just file contexts reusing standard
# Fedora types. Adapted from nix-community/nix-installers/selinux, the
# policy Fedora adopted in selinux-policy PR #3454. Compiled at the
# current policy version (matches build/selinux/borgmatic/Makefile).
.PHONY: all clean install uninstall validate

all: $(PP_FILE)

$(PP_FILE): $(MOD_FILE)
	@echo "Packaging SELinux policy module..."
	semodule_package -o $@ -m $< -f $(FC_FILE)

$(MOD_FILE): $(TE_FILE)
	@echo "Compiling SELinux policy module..."
	checkmodule -M -m -o $@ $<

clean:
	@echo "Cleaning up..."
	rm -f *.mod *.pp

install: $(PP_FILE)
	@echo "Installing SELinux policy module..."
	semodule -i $<

uninstall:
	@echo "Uninstalling SELinux policy module..."
	semodule -r $(POLICY_NAME)

validate: $(TE_FILE)
	@echo "Validating policy files..."
	checkmodule -C -m $<
