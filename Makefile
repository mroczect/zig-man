# zig-man

PREFIX   ?= /usr/local
MANDIR   ?= $(PREFIX)/share/man
DESTDIR  ?=
BUILDDIR ?= build
INSTALL  ?= install
SECTIONS := 1 3 5 7
PAGES    := $(wildcard man/man*/*.[1-9])

ZM_VER     := Zig 0.17.0
ZM_MANUAL  := Zig Manual
ZM_AUTHOR  := mroczect and contributors
ZM_SOURCE  := https://github.com/mroczect/zig-man
ZM_LICENSE := CC BY-SA 4.0

.PHONY: all install uninstall lint preview html pdf txt watch spell \
        check ci check-strict check-meta format format-header format-footer \
        install-hooks clean

all:
	@echo "zig-man: nothing to build. Run 'make install'."

install:
	@set -e; \
	for s in $(SECTIONS); do \
		src=man/man$$s; \
		dst=$(DESTDIR)$(MANDIR)/man$$s; \
		[ -d "$$src" ] || continue; \
		set -- "$$src"/*.$$s; \
		[ -e "$$1" ] || continue; \
		$(INSTALL) -d "$$dst"; \
		$(INSTALL) -m 644 "$$@" "$$dst"; \
	done
	@command -v mandb >/dev/null 2>&1 && mandb -q >/dev/null 2>&1 || true

uninstall:
	@set -e; \
	for s in $(SECTIONS); do \
		src=man/man$$s; \
		dst=$(DESTDIR)$(MANDIR)/man$$s; \
		[ -d "$$src" ] || continue; \
		set -- "$$src"/*.$$s; \
		[ -e "$$1" ] || continue; \
		for f in "$$@"; do rm -f "$$dst/$$(basename $$f)"; done; \
	done

install-hooks:
	@git config core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "hooks installed (.githooks)"

lint:
	@command -v mandoc >/dev/null 2>&1 || { echo "mandoc not found" >&2; exit 1; }
	@[ -n "$(PAGES)" ] || { echo "no pages to lint"; exit 0; }
	@mandoc -T lint $(PAGES)

check-meta:
	@bad=0; \
	for f in $(PAGES); do \
		sec=$${f##*.}; \
		base=$$(basename "$$f" ".$$sec"); \
		name=$$(echo "$$base" | tr 'a-z-' 'A-Z_'); \
		date=$$(git log -1 --format=%as -- "$$f" 2>/dev/null); \
		[ -n "$$date" ] || date=$$(date +%F); \
		expect=".TH $$name $$sec \"$$date\" \"$(ZM_VER)\" \"$(ZM_MANUAL)\""; \
		actual=$$(head -1 "$$f"); \
		if [ "$$actual" != "$$expect" ]; then \
			echo "$$f: stale .TH"; \
			echo "  want: $$expect"; \
			echo "  got:  $$actual"; \
			bad=1; \
		fi; \
		for s in AUTHORS COPYRIGHT SOURCE; do \
			grep -q "^\.SH $$s$$" "$$f" || { echo "$$f: missing .SH $$s"; bad=1; }; \
		done; \
	done; \
	exit $$bad

check-refs:
	@missing=0; \
	for f in $(PAGES); do \
		refs=$$(grep -oE '\.(BR|IR|RI) +[a-z][a-z0-9_-]+ *\([1-9]\)' "$$f" \
			| grep -oE '[a-z][a-z0-9_-]+' | sort -u); \
		for r in $$refs; do \
			found=$$(find man -name "$$r.[1-9]" -print -quit); \
			[ -n "$$found" ] || { echo "missing: $$r (referenced in $$f)"; missing=1; }; \
		done; \
	done; \
	[ $$missing -eq 0 ] && echo "all cross-references resolved" || true

check: check-meta check-refs

check-strict: check-meta
	@missing=0; \
	for f in $(PAGES); do \
		refs=$$(grep -oE '\.(BR|IR|RI) +[a-z][a-z0-9_-]+ *\([1-9]\)' "$$f" \
			| grep -oE '[a-z][a-z0-9_-]+' | sort -u); \
		for r in $$refs; do \
			found=$$(find man -name "$$r.[1-9]" -print -quit); \
			[ -n "$$found" ] || { echo "missing: $$r (referenced in $$f)"; missing=1; }; \
		done; \
	done; \
	exit $$missing

preview:
	@[ -n "$(FILE)" ] || { echo "usage: make preview FILE=man/man7/x.7" >&2; exit 1; }
	@man -l $(FILE)

html:
	@command -v mandoc >/dev/null 2>&1 || { echo "mandoc not found" >&2; exit 1; }
	@mkdir -p $(BUILDDIR)/html
	@for f in $(PAGES); do \
		out=$(BUILDDIR)/html/$$(basename $$f .$${f##*.}).html; \
		mandoc -T html "$$f" > "$$out"; \
	done
	@echo "html -> $(BUILDDIR)/html/"

pdf:
	@mkdir -p $(BUILDDIR)/pdf
	@for f in $(PAGES); do \
		out=$(BUILDDIR)/pdf/$$(basename $$f .$${f##*.}).pdf; \
		if groff -man -Tpdf /dev/null >/dev/null 2>&1; then \
			groff -man -Tpdf "$$f" > "$$out"; \
		elif command -v ps2pdf >/dev/null 2>&1; then \
			groff -man -Tps "$$f" | ps2pdf - "$$out"; \
		else \
			echo "no PDF backend: install ghostscript" >&2; \
			exit 1; \
		fi; \
	done
	@echo "pdf -> $(BUILDDIR)/pdf/"

txt:
	@command -v mandoc >/dev/null 2>&1 || { echo "mandoc not found" >&2; exit 1; }
	@mkdir -p $(BUILDDIR)/txt
	@for f in $(PAGES); do \
		out=$(BUILDDIR)/txt/$$(basename $$f .$${f##*.}).txt; \
		mandoc -T utf8 "$$f" | col -b > "$$out"; \
	done
	@echo "txt -> $(BUILDDIR)/txt/"

watch:
	@[ -n "$(FILE)" ] || { echo "usage: make watch FILE=man/man7/x.7" >&2; exit 1; }
	@if command -v entr >/dev/null 2>&1; then \
		echo "$(FILE)" | entr -c man -l $(FILE); \
	elif command -v inotifywait >/dev/null 2>&1; then \
		while inotifywait -q -e close_write "$(FILE)"; do clear; man -l $(FILE); done; \
	else \
		echo "need entr or inotifywait" >&2; exit 1; \
	fi

spell:
	@if command -v hunspell >/dev/null 2>&1; then \
		for f in $(PAGES); do hunspell -l -p .aspell "$$f"; done | sort -u; \
	elif command -v aspell >/dev/null 2>&1; then \
		for f in $(PAGES); do aspell list --personal=.aspell < "$$f"; done | sort -u; \
	else echo "no spell checker" >&2; exit 1; \
	fi

format-header:
	@for f in $(PAGES); do \
		sec=$${f##*.}; \
		base=$$(basename "$$f" ".$$sec"); \
		name=$$(echo "$$base" | tr 'a-z-' 'A-Z_'); \
		date=$$(git log -1 --format=%as -- "$$f" 2>/dev/null); \
		[ -n "$$date" ] || date=$$(date +%F); \
		sed -i "1s|^\.TH .*|.TH $$name $$sec \"$$date\" \"$(ZM_VER)\" \"$(ZM_MANUAL)\"|" "$$f"; \
		echo "  $$f -> $$date"; \
	done

format-footer:
	@for f in $(PAGES); do \
		year=$$(git log -1 --format=%ad --date=format:%Y -- "$$f" 2>/dev/null); \
		[ -n "$$year" ] || year=$$(date +%Y); \
		awk -v author='$(ZM_AUTHOR)' -v year="$$year" -v src='$(ZM_SOURCE)' \
		    -v lic='$(ZM_LICENSE)' '\
			BEGIN { skip=0 } \
			/^\.SH AUTHORS$$/ { skip=1; next } \
			skip { next } \
			{ print } \
			END { \
				print ".SH AUTHORS"; \
				print author "."; \
				print ".SH COPYRIGHT"; \
				print "Copyright \\(co " year " mroczect."; \
				print "Licensed under " lic "."; \
				print ".SH SOURCE"; \
				print src; \
			}' "$$f" > "$$f.tmp" && mv "$$f.tmp" "$$f"; \
		echo "  $$f -> (c) $$year"; \
	done

format: format-header format-footer
	@echo "format: done"

spell-strict:
	@command -v hunspell >/dev/null 2>&1 || { echo "hunspell not found" >&2; exit 1; }
	@out=$$(for f in $(PAGES); do hunspell -l -p .aspell "$$f"; done | sort -u); \
	if [ -n "$$out" ]; then \
		echo "$$out"; \
		echo "spell: misspelled words (add to .aspell or fix the source)" >&2; \
		exit 1; \
	fi
	@echo "spell: clean"

ci: lint check-strict spell-strict
	@echo "ci: all checks passed"
clean:
	@rm -rf $(BUILDDIR)
