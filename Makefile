CHAPTERS := $(wildcard course/*.md)
EPUB := backend-roadmap.epub

.PHONY: all epub clean

all: epub

epub: $(EPUB)

$(EPUB): $(CHAPTERS)
	pandoc $^ -o $@ \
		--metadata title="Backend API con Python" \
		--metadata author="Matteo Garza" \
		--toc \
		--toc-depth=2

clean:
	rm -f $(EPUB)
