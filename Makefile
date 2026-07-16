CHAPTERS := $(wildcard course/*.md)
EPUB := backend-roadmap.epub
SOURCES := $(CHAPTERS) LICENSE
MDFILES := course/*.md docs/*.md ROADMAP.md README.md

.PHONY: all epub lint spellcheck linkcheck format check clean

all: check epub

check: lint spellcheck linkcheck

epub: $(EPUB)

lint:
	npx markdownlint-cli $(MDFILES)

spellcheck:
	codespell $(MDFILES)

linkcheck:
	lychee $(MDFILES)

format:
	npx prettier --write $(MDFILES)

$(EPUB): $(SOURCES)
	pandoc $^ -o $@ \
		--metadata title="Backend API con Python" \
		--metadata author="Matteo Garza" \
		--toc \
		--toc-depth=2

clean:
	rm -f $(EPUB)
