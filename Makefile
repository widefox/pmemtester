NAME    := pmemtester
VERSION := 0.1
PREFIX  := /usr/local

.PHONY: test test-unit test-integration coverage lint clean dist install uninstall

test: test-unit test-integration

test-unit:
	bats test/unit/

test-integration:
	bats test/integration/

coverage:
	kcov --include-path=./lib,./pmemtester ./coverage bats test/unit/ test/integration/
	@echo "Coverage report: ./coverage/index.html"

lint:
	shellcheck -s bash lib/*.sh pmemtester

dist:
	@mkdir -p dist
	tar czf dist/$(NAME)-$(VERSION).tgz \
		--transform='s,^,$(NAME)-$(VERSION)/,' \
		pmemtester lib/ Makefile README.md CLAUDE.md
	@echo "Created dist/$(NAME)-$(VERSION).tgz"

install:
	install -d $(DESTDIR)$(PREFIX)/bin
	install -d $(DESTDIR)$(PREFIX)/lib/$(NAME)
	install -m 755 pmemtester $(DESTDIR)$(PREFIX)/bin/pmemtester
	install -m 644 lib/*.sh $(DESTDIR)$(PREFIX)/lib/$(NAME)/
	@# Patch installed script to source from installed lib location
	sed -i 's|"$${SCRIPT_DIR}"/lib|$(PREFIX)/lib/$(NAME)|' $(DESTDIR)$(PREFIX)/bin/pmemtester
	@echo "Installed $(NAME) $(VERSION) to $(PREFIX)"

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/pmemtester
	rm -rf $(DESTDIR)$(PREFIX)/lib/$(NAME)
	@echo "Uninstalled $(NAME) from $(PREFIX)"

clean:
	rm -rf coverage/ dist/ test/tmp/
