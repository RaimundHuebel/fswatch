###
# Makefile for fswatch project.
# @author Raimund Hübel <raimund.huebel@googlemail.com>
###

.PHONY: default
default: build


.PHONY: build
build: dist


.PHONY: dist
dist: dist/release dist/debug dist/doc


.PHONY: dist/release
dist/release:
	mkdir -p dist/release
	#nimble build -o:dist/release/highlight -d:release --opt:size fswatch
	nim compile -o:dist/release/fswatch -d:release --opt:size src/fswatch.nim
	-strip --strip-all dist/release/fswatch
	-upx --best dist/release/fswatch


.PHONY: dist/debug
dist/debug:
	mkdir -p dist/debug
	#nimble build -o:dist/debug/fswatch -d:allow_debug_mode fswatch
	nim compile -o:dist/debug/fswatch -d:allow_debug_mode src/fswatch.nim


.PHONY: dist/doc
dist/doc:
	# see: https://nim-lang.org/docs/docgen.html
	rm -rf dist/doc
	mkdir -p dist/doc
	cd dist/doc && nim doc --project --index:on ../../src/fswatch.nim
	cd dist/doc && nim buildIndex -o:index.html ./


.PHONY: test
test:
	nimble test


.PHONY: clean
clean:
	rm -rf dist fswatch

.PHONY: mrproper
mrproper: clean


.PHONY: distclean
distclean:
	git clean -fdx .
