# lamboot-tools — build and install
#
# Governed by SPEC-LAMBOOT-TOOLKIT-V1.md §6.2 + §7.2.
#
# Two install forms:
#
#   make install           Sourced form: tools source /usr/lib/lamboot-tools/lib.sh
#                          Used by distro packages (Copr, PPA)
#
#   make install-inlined   Inlined form: library concatenated into each tool
#                          Used by tarball, curl-pipe, rescue-media deployment
#
# Every tool has both forms. Inlined is tested identically to sourced in CI.

PREFIX      ?= /usr/local
BINDIR      ?= $(PREFIX)/bin
LIBDIR      ?= $(PREFIX)/lib/lamboot-tools
MANDIR      ?= $(PREFIX)/share/man
DOCDIR      ?= $(PREFIX)/share/doc/lamboot-tools
DESTDIR     ?=

BUILD_DIR   = build
SOURCED_DIR = $(BUILD_DIR)/sourced
INLINED_DIR = $(BUILD_DIR)/inlined

LIB_FILES   = lib/lamboot-toolkit-lib.sh lib/lamboot-toolkit-help.sh

CORE_TOOLS = \
    lamboot-diagnose \
    lamboot-esp \
    lamboot-backup \
    lamboot-repair \
    lamboot-migrate \
    lamboot-doctor \
    lamboot-toolkit \
    lamboot-uki-build \
    lamboot-signing-keys

# lamboot-inspect is mirrored at release-build time from lamboot-dev/tools/;
# not built from sources in this repo.

# PVE companion tools — live under pve/tools/ in this repo.
# Built from the same source tree; ship as the lamboot-toolkit-pve RPM
# subpackage (see packaging/rpm/lamboot-tools.spec).
# Makefile-level install-pve target provided for dev-tree local installation.
PVE_TOOLS = \
    lamboot-pve-setup \
    lamboot-pve-fleet
# lamboot-pve-monitor + lamboot-pve-ovmf-vars are mirrored from lamboot-dev
# (see publish/mirror-pve-from-lamboot-dev.sh)

INSTALL ?= install

.PHONY: all build build-sourced build-inlined install install-inlined uninstall \
        clean test lint help

all: build

help:
	@echo "lamboot-tools Makefile targets:"
	@echo "  build              Build both sourced and inlined forms (core)"
	@echo "  build-sourced      Build tools that source the library at runtime"
	@echo "  build-inlined      Build tools with the library concatenated"
	@echo "  install            Install sourced form (distro-package target)"
	@echo "  install-inlined    Install inlined form (tarball target)"
	@echo "  install-pve        Install PVE companion tools (dev-tree local)"
	@echo "  uninstall          Remove every installed artifact"
	@echo "  test               Run the bats-core test suite"
	@echo "  lint               Run shellcheck on every bash file"
	@echo "  clean              Remove build/ artifacts"
	@echo "  mirror-lamboot-dev Run publish/mirror-from-lamboot-dev.sh"
	@echo "  mirror-pve         Run publish/mirror-pve-from-lamboot-dev.sh"
	@echo "  man                Regenerate man pages from help registry"
	@echo "  website            Regenerate website tool pages from help registry"
	@echo "  serve-website      Run mkdocs dev server at http://127.0.0.1:8001"
	@echo "  build-website      Build static site to website/build/"
	@echo "  test               Run core bats CLI tests (fast, no fixtures)"
	@echo "  test-integration   Run integration tests (requires fixtures + root)"
	@echo "  test-pve           Run PVE companion bats tests"
	@echo "  test-all           Run all three test suites"
	@echo "  fixtures           Download fixture disk images"
	@echo "  fleet-test         Run Tier 1 fleet test (requires Proxmox host)"

build: build-sourced build-inlined

build-sourced: $(SOURCED_DIR)/.stamp

$(SOURCED_DIR)/.stamp: $(LIB_FILES) $(foreach t,$(CORE_TOOLS),tools/$(t))
	@mkdir -p $(SOURCED_DIR)
	@for tool in $(CORE_TOOLS); do \
	    if [ -f tools/$$tool ]; then \
	        cp tools/$$tool $(SOURCED_DIR)/$$tool; \
	        chmod +x $(SOURCED_DIR)/$$tool; \
	    fi; \
	done
	@touch $@

build-inlined: $(INLINED_DIR)/.stamp

$(INLINED_DIR)/.stamp: $(LIB_FILES) $(foreach t,$(CORE_TOOLS),tools/$(t))
	@mkdir -p $(INLINED_DIR)
	@for tool in $(CORE_TOOLS); do \
	    if [ -f tools/$$tool ]; then \
	        ./scripts/inline-tool tools/$$tool > $(INLINED_DIR)/$$tool; \
	        chmod +x $(INLINED_DIR)/$$tool; \
	    fi; \
	done
	@touch $@

install: build-sourced
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL) -d $(DESTDIR)$(LIBDIR)
	$(INSTALL) -d $(DESTDIR)$(MANDIR)/man1
	$(INSTALL) -d $(DESTDIR)$(MANDIR)/man5
	$(INSTALL) -d $(DESTDIR)$(MANDIR)/man7
	$(INSTALL) -d $(DESTDIR)$(DOCDIR)
	@for lib in $(LIB_FILES); do \
	    $(INSTALL) -m 644 $$lib $(DESTDIR)$(LIBDIR)/$$(basename $$lib); \
	    echo "  installed $(LIBDIR)/$$(basename $$lib)"; \
	done
	@for tool in $(CORE_TOOLS); do \
	    if [ -f $(SOURCED_DIR)/$$tool ]; then \
	        $(INSTALL) -m 755 $(SOURCED_DIR)/$$tool $(DESTDIR)$(BINDIR)/$$tool; \
	        echo "  installed $(BINDIR)/$$tool"; \
	    fi; \
	done
	@# lamboot-inspect is a Python script + sibling lamboot_inspect/ package,
	@# mirrored from lamboot-dev at release-build time. Its _bootstrap() adds
	@# dirname(realpath(__file__)) to sys.path, so both must live in the same
	@# directory — we install to $(LIBDIR) and symlink $(BINDIR)/lamboot-inspect.
	@if [ -f tools/lamboot-inspect ]; then \
	    $(INSTALL) -m 755 tools/lamboot-inspect $(DESTDIR)$(LIBDIR)/lamboot-inspect; \
	    ln -sf $(LIBDIR)/lamboot-inspect $(DESTDIR)$(BINDIR)/lamboot-inspect; \
	    echo "  installed $(BINDIR)/lamboot-inspect -> $(LIBDIR)/lamboot-inspect"; \
	fi
	@if [ -d tools/lamboot_inspect ]; then \
	    cp -a tools/lamboot_inspect $(DESTDIR)$(LIBDIR)/; \
	    find $(DESTDIR)$(LIBDIR)/lamboot_inspect -type f -exec chmod 644 {} +; \
	    find $(DESTDIR)$(LIBDIR)/lamboot_inspect -type d -exec chmod 755 {} +; \
	    echo "  installed $(LIBDIR)/lamboot_inspect/"; \
	fi
	@for page in man/*.1; do \
	    [ -f $$page ] || continue; \
	    $(INSTALL) -m 644 $$page $(DESTDIR)$(MANDIR)/man1/; \
	done
	@for page in man/*.5; do \
	    [ -f $$page ] || continue; \
	    $(INSTALL) -m 644 $$page $(DESTDIR)$(MANDIR)/man5/; \
	done
	@for page in man/*.7; do \
	    [ -f $$page ] || continue; \
	    $(INSTALL) -m 644 $$page $(DESTDIR)$(MANDIR)/man7/; \
	done
	@if [ -f CHANGELOG.md ]; then \
	    $(INSTALL) -m 644 CHANGELOG.md $(DESTDIR)$(DOCDIR)/; \
	fi
	@if [ -f README.md ]; then \
	    $(INSTALL) -m 644 README.md $(DESTDIR)$(DOCDIR)/; \
	fi
	@if [ -f LICENSE-MIT ]; then \
	    $(INSTALL) -m 644 LICENSE-MIT $(DESTDIR)$(DOCDIR)/; \
	fi
	@if [ -f LICENSE-APACHE ]; then \
	    $(INSTALL) -m 644 LICENSE-APACHE $(DESTDIR)$(DOCDIR)/; \
	fi

install-inlined: build-inlined
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL) -d $(DESTDIR)$(LIBDIR)
	$(INSTALL) -d $(DESTDIR)$(MANDIR)/man1
	$(INSTALL) -d $(DESTDIR)$(MANDIR)/man5
	$(INSTALL) -d $(DESTDIR)$(MANDIR)/man7
	$(INSTALL) -d $(DESTDIR)$(DOCDIR)
	@for tool in $(CORE_TOOLS); do \
	    if [ -f $(INLINED_DIR)/$$tool ]; then \
	        $(INSTALL) -m 755 $(INLINED_DIR)/$$tool $(DESTDIR)$(BINDIR)/$$tool; \
	        echo "  installed (inlined) $(BINDIR)/$$tool"; \
	    fi; \
	done
	@# Same lamboot-inspect handling as install: (see that target for rationale)
	@if [ -f tools/lamboot-inspect ]; then \
	    $(INSTALL) -m 755 tools/lamboot-inspect $(DESTDIR)$(LIBDIR)/lamboot-inspect; \
	    ln -sf $(LIBDIR)/lamboot-inspect $(DESTDIR)$(BINDIR)/lamboot-inspect; \
	fi
	@if [ -d tools/lamboot_inspect ]; then \
	    cp -a tools/lamboot_inspect $(DESTDIR)$(LIBDIR)/; \
	    find $(DESTDIR)$(LIBDIR)/lamboot_inspect -type f -exec chmod 644 {} +; \
	    find $(DESTDIR)$(LIBDIR)/lamboot_inspect -type d -exec chmod 755 {} +; \
	fi
	@for page in man/*.1; do \
	    [ -f $$page ] || continue; \
	    $(INSTALL) -m 644 $$page $(DESTDIR)$(MANDIR)/man1/; \
	done
	@for page in man/*.5; do \
	    [ -f $$page ] || continue; \
	    $(INSTALL) -m 644 $$page $(DESTDIR)$(MANDIR)/man5/; \
	done
	@for page in man/*.7; do \
	    [ -f $$page ] || continue; \
	    $(INSTALL) -m 644 $$page $(DESTDIR)$(MANDIR)/man7/; \
	done

uninstall:
	@for tool in $(CORE_TOOLS); do \
	    rm -f $(DESTDIR)$(BINDIR)/$$tool; \
	    echo "  removed $(BINDIR)/$$tool"; \
	done
	@rm -f $(DESTDIR)$(BINDIR)/lamboot-inspect
	@rm -f $(DESTDIR)$(LIBDIR)/lamboot-inspect
	@rm -rf $(DESTDIR)$(LIBDIR)/lamboot_inspect
	@rm -f $(DESTDIR)$(LIBDIR)/lamboot-toolkit-lib.sh
	@rm -f $(DESTDIR)$(LIBDIR)/lamboot-toolkit-help.sh
	@rmdir $(DESTDIR)$(LIBDIR) 2>/dev/null || true
	@for page in man/*.1 man/*.5 man/*.7; do \
	    [ -f $$page ] || continue; \
	    rm -f $(DESTDIR)$(MANDIR)/man1/$$(basename $$page); \
	    rm -f $(DESTDIR)$(MANDIR)/man5/$$(basename $$page); \
	    rm -f $(DESTDIR)$(MANDIR)/man7/$$(basename $$page); \
	done
	@rm -rf $(DESTDIR)$(DOCDIR)

test:
	@if command -v bats >/dev/null 2>&1; then \
	    bats tests/*.bats; \
	else \
	    echo "bats not installed; install bats-core to run tests" >&2; \
	    exit 1; \
	fi

test-integration:
	@if command -v bats >/dev/null 2>&1; then \
	    bats tests/integration/*.bats; \
	else \
	    echo "bats not installed" >&2; \
	    exit 1; \
	fi

test-pve:
	@if command -v bats >/dev/null 2>&1; then \
	    bats pve/tests/*.bats; \
	else \
	    echo "bats not installed" >&2; \
	    exit 1; \
	fi

test-all: test test-integration test-pve
	@echo "  all test suites complete"

fleet-test:
	scripts/fleet-test.sh

fixtures:
	tests/fixtures/download-fixtures.sh

lint:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
	    echo "shellcheck not installed" >&2; \
	    exit 1; \
	fi
	@failures=0; \
	for f in lib/*.sh tools/lamboot-* .githooks/pre-commit scripts/*; do \
	    [ -f "$$f" ] || continue; \
	    case "$$f" in *.py|*.pyc) continue ;; esac; \
	    if head -1 "$$f" | grep -qE '^#!.*(bash|sh)'; then \
	        if ! shellcheck --severity=style --external-sources "$$f"; then \
	            failures=$$((failures + 1)); \
	        fi; \
	    fi; \
	done; \
	if [ $$failures -gt 0 ]; then \
	    echo "$$failures file(s) failed shellcheck" >&2; \
	    exit 1; \
	fi; \
	echo "  shellcheck clean"

install-pve: build-sourced
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	@for tool in $(PVE_TOOLS); do \
	    if [ -f pve/tools/$$tool ]; then \
	        $(INSTALL) -m 755 pve/tools/$$tool $(DESTDIR)$(BINDIR)/$$tool; \
	        echo "  installed (pve) $(BINDIR)/$$tool"; \
	    fi; \
	done
	@if [ -f pve/tools/lamboot-pve-monitor ]; then \
	    $(INSTALL) -m 755 pve/tools/lamboot-pve-monitor $(DESTDIR)$(BINDIR)/lamboot-pve-monitor; \
	    echo "  installed (pve mirror) $(BINDIR)/lamboot-pve-monitor"; \
	fi
	@if [ -f pve/tools/lamboot-pve-ovmf-vars ]; then \
	    $(INSTALL) -m 755 pve/tools/lamboot-pve-ovmf-vars $(DESTDIR)$(BINDIR)/lamboot-pve-ovmf-vars; \
	    echo "  installed (pve mirror) $(BINDIR)/lamboot-pve-ovmf-vars"; \
	fi

mirror-lamboot-dev:
	publish/mirror-from-lamboot-dev.sh

mirror-pve:
	publish/mirror-pve-from-lamboot-dev.sh

man: $(foreach t,$(CORE_TOOLS),man/$(t).1) $(foreach t,$(PVE_TOOLS),man/$(t).1)
	@echo "  man pages generated"

# Per-tool man generation rule
man/%.1: tools/% scripts/registry-to-man lib/lamboot-toolkit-help.sh
	@mkdir -p man
	@scripts/registry-to-man $< man/ >/dev/null
	@echo "  generated man/$$(basename $@)"

# PVE companion man generation
$(foreach t,$(PVE_TOOLS),man/$(t).1): man/%.1: pve/tools/% scripts/registry-to-man lib/lamboot-toolkit-help.sh
	@mkdir -p man
	@scripts/registry-to-man $< man/ >/dev/null
	@echo "  generated man/$$(basename $@)"

# Website content generation from help registry (§10 of toolkit spec)
website: $(foreach t,$(CORE_TOOLS),website/tools/$(t).md) $(foreach t,$(PVE_TOOLS),website/tools/$(t).md)
	@echo "  website tool pages generated"

website/tools/%.md: tools/% scripts/registry-to-markdown lib/lamboot-toolkit-help.sh
	@mkdir -p website/tools
	@scripts/registry-to-markdown $< website/tools/ >/dev/null
	@echo "  generated website/tools/$$(basename $@)"

$(foreach t,$(PVE_TOOLS),website/tools/$(t).md): website/tools/%.md: pve/tools/% scripts/registry-to-markdown lib/lamboot-toolkit-help.sh
	@mkdir -p website/tools
	@scripts/registry-to-markdown $< website/tools/ >/dev/null
	@echo "  generated website/tools/$$(basename $@)"

serve-website:
	@cd website && mkdocs serve -a 127.0.0.1:8001

build-website: website
	@cd website && mkdocs build -d build/ 2>&1 | tail -20

clean:
	rm -rf $(BUILD_DIR)
