# interscript-py developer tasks.
# Source files carry the BSD-3-Clause header; see LICENSE.

PYTHON ?= python3
ARTIFACT_DIR ?= /tmp/isir

.PHONY: test test-full test-ml lint build-artifact

test:            ## map runtime: unit tests + embedded corpus over the bundled subset
	$(PYTHON) -m pytest

test-full:       ## embedded corpus over a full compiled artifact
	INTERSCRIPT_MAPS_IR=$(ARTIFACT_DIR) $(PYTHON) -m pytest tests/test_embedded_map_tests.py

test-ml:         ## frozen model vector families with local zips (needs interscript-py[ml])
	$(PYTHON) -m pytest -m ml

lint:            ## ruff over src and tests (if installed)
	$(PYTHON) -m ruff check src tests || echo "ruff not installed — skipping"

build-artifact:  ## rebuild the compiled JSON-IR artifact from the maps repo
	scripts/build_maps_ir.sh ~/src/interscript/maps ~/src/interscript/interscript-ts $(ARTIFACT_DIR)
