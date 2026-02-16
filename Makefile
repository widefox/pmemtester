NAME    := pmemtester
VERSION := 0.3
PREFIX  := /usr/local

.PHONY: test test-unit test-integration coverage lint clean dist install uninstall

test: test-unit test-integration

test-unit:
	bats test/unit/

test-integration:
	bats test/integration/

coverage:
	kcov --include-path=./lib,./pmemtester ./coverage $(shell which bats) test/unit/ test/integration/
	@echo "Coverage report: ./coverage/index.html"

lint:
	shellcheck -s bash lib/*.sh pmemtester

dist:
	@mkdir -p dist
	tar czf dist/$(NAME)-$(VERSION).tgz \
		--transform='s,^,$(NAME)-$(VERSION)/,' \
		pmemtester lib/ Makefile README.md CHANGELOG.md FAQ.md TODO.md PROMPT.md CLAUDE.md
	@echo "Created dist/$(NAME)-$(VERSION).tgz"

install:
	install -d $(DESTDIR)$(PREFIX)/bin
	install -d $(DESTDIR)$(PREFIX)/lib/$(NAME)
	install -m 755 pmemtester $(DESTDIR)$(PREFIX)/bin/pmemtester
	install -m 644 lib/*.sh $(DESTDIR)$(PREFIX)/lib/$(NAME)/
	@# Patch installed script to source from installed lib location
	sed -i 's|"$${SCRIPT_DIR}"/lib|$(PREFIX)/lib/$(NAME)|' $(DESTDIR)$(PREFIX)/bin/pmemtester
ifdef MEMTESTER_DIR
	@# Patch default memtester directory for distro packaging (e.g., /usr/bin)
	sed -i 's|DEFAULT_MEMTESTER_DIR="$${DEFAULT_MEMTESTER_DIR:-/usr/local/bin}"|DEFAULT_MEMTESTER_DIR="$(MEMTESTER_DIR)"|' $(DESTDIR)$(PREFIX)/lib/$(NAME)/cli.sh
endif
ifdef STRESSAPPTEST_DIR
	@# Patch default stressapptest directory for distro packaging
	sed -i 's|DEFAULT_STRESSAPPTEST_DIR="$${DEFAULT_STRESSAPPTEST_DIR:-/usr/local/bin}"|DEFAULT_STRESSAPPTEST_DIR="$(STRESSAPPTEST_DIR)"|' $(DESTDIR)$(PREFIX)/lib/$(NAME)/cli.sh
endif
	@echo "Installed $(NAME) $(VERSION) to $(PREFIX)"

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/pmemtester
	rm -rf $(DESTDIR)$(PREFIX)/lib/$(NAME)
	@echo "Uninstalled $(NAME) from $(PREFIX)"

clean:
	rm -rf coverage/ dist/ test/tmp/
