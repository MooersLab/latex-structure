# Makefile for latex-structure
#
# Run `make help' for the list of targets.  Every tool path is a
# variable, so you can override it on the command line, for example
#
#   make test EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs

SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- Tool configuration ---
EMACS        ?= emacs
MAKEINFO     ?= makeinfo
PANDOC       ?= pandoc
GIT          ?= git
PYTHON       ?= python3
COVERAGE_MIN ?= 90
DOCS_MIN     ?= 90
DOCS_PORT    ?= 8000

PACKAGE      := latex-structure
SRC_DIR      ?= .
TEST_DIR     ?= test
DEPS_DIR     ?= .deps
DOCS_DIR     ?= docs
DOCS_BUILD   ?= $(DOCS_DIR)/site

SRC_FILES    := $(PACKAGE).el
TEST_HELPER  := $(TEST_DIR)/$(PACKAGE)-test-helper.el
UNIT_TESTS   := $(TEST_DIR)/$(PACKAGE)-test.el
INTEG_TESTS  := $(TEST_DIR)/$(PACKAGE)-integration-test.el
# Only the test files that exist.  latex-structure has a single unit
# test file today; a helper or an integration file is picked up when
# it is added.
TEST_FILES   := $(wildcard $(UNIT_TESTS) $(INTEG_TESTS))

ORG_MANUAL   := $(DOCS_DIR)/$(PACKAGE).org
TEXI_MANUAL  := $(DOCS_DIR)/$(PACKAGE).texi
INFO_MANUAL  := $(DOCS_DIR)/$(PACKAGE).info
API_MD       := $(DOCS_DIR)/api/$(PACKAGE)-api.md

# Optional checkouts used by the tests, the linter, and coverage.
# `make install-test-deps' clones them into $(DEPS_DIR).
AUCTEX_DIR       ?= $(DEPS_DIR)/auctex
PACKAGE_LINT_DIR ?= $(DEPS_DIR)/package-lint
UNDERCOVER_DIR   ?= $(DEPS_DIR)/undercover.el
DASH_DIR         ?= $(DEPS_DIR)/dash.el
SHUT_UP_DIR      ?= $(DEPS_DIR)/shut-up

# Add each optional directory to the load path only when it exists.
opt_load = $(foreach d,$(1),$(if $(wildcard $(d)),-L $(d)))
LOAD_PATH  := -L $(SRC_DIR) -L $(TEST_DIR) $(call opt_load,$(AUCTEX_DIR))
COV_PATH   := $(call opt_load,$(UNDERCOVER_DIR) $(DASH_DIR) $(SHUT_UP_DIR))
BATCH      := $(EMACS) -Q --batch

# --- Colors (only when a terminal is present) ---
ifneq ($(TERM),)
  GREEN  := \033[0;32m
  RED    := \033[0;31m
  YELLOW := \033[0;33m
  RESET  := \033[0m
else
  GREEN  :=
  RED    :=
  YELLOW :=
  RESET  :=
endif

.PHONY: all help compile clean install-test-deps \
        test test-unit test-integration \
        coverage coverage-html coverage-check \
        lint lint-compile lint-checkdoc lint-package \
        docs docs-serve docs-clean docs-check docs-open docs-api \
        docs-lint docs-deps texi info html

# The docs step runs only once the Org manual exists.
all: compile lint test $(if $(wildcard $(ORG_MANUAL)),docs) ## Compile, lint, test, and build the docs if present

help: ## Show this help message
	@echo "Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

compile: ## Byte-compile the package and fail on any warning
	@echo -e "$(YELLOW)Byte-compiling...$(RESET)"
	@$(BATCH) -L $(SRC_DIR) \
		--eval '(setq byte-compile-error-on-warn t)' \
		-f batch-byte-compile $(SRC_FILES)
	@echo -e "$(GREEN)Compiled without warnings.$(RESET)"

# --- maketests: auto-generated targets (begin) ---

install-test-deps: ## Clone AUCTeX, package-lint, undercover, dash, shut-up into .deps
	@echo -e "$(YELLOW)Installing test dependencies into $(DEPS_DIR)...$(RESET)"
	@mkdir -p $(DEPS_DIR)
	@[ -d $(AUCTEX_DIR) ] || $(GIT) clone --depth 1 https://github.com/emacs-straight/auctex.git $(AUCTEX_DIR)
	@[ -d $(PACKAGE_LINT_DIR) ] || $(GIT) clone --depth 1 https://github.com/purcell/package-lint.git $(PACKAGE_LINT_DIR)
	@[ -d $(UNDERCOVER_DIR) ] || $(GIT) clone --depth 1 https://github.com/undercover-el/undercover.el.git $(UNDERCOVER_DIR)
	@[ -d $(DASH_DIR) ] || $(GIT) clone --depth 1 https://github.com/magnars/dash.el.git $(DASH_DIR)
	@[ -d $(SHUT_UP_DIR) ] || $(GIT) clone --depth 1 https://github.com/Wilfred/shut-up.git $(SHUT_UP_DIR)
	@echo -e "$(GREEN)Dependencies installed.$(RESET)"

test: ## Run all tests (unit + integration) via ERT
	@echo -e "$(YELLOW)Running all tests...$(RESET)"
	@rm -f $(SRC_DIR)/*.elc
	@$(BATCH) $(LOAD_PATH) \
		$(foreach f,$(TEST_FILES),-l $(f)) \
		-f ert-run-tests-batch-and-exit
	@echo -e "$(GREEN)All tests passed.$(RESET)"

test-unit: ## Run unit tests only (tests without the integration tag)
	@echo -e "$(YELLOW)Running unit tests...$(RESET)"
	@rm -f $(SRC_DIR)/*.elc
	@$(BATCH) $(LOAD_PATH) -l $(UNIT_TESTS) \
		--eval '(ert-run-tests-batch-and-exit (quote (not (tag integration))))'
	@echo -e "$(GREEN)Unit tests passed.$(RESET)"

test-integration: ## Run integration tests only (command loop and AUCTeX)
	@[ -f $(INTEG_TESTS) ] || { echo -e "$(YELLOW)No $(INTEG_TESTS) yet; nothing to run.$(RESET)"; exit 0; }; \
	echo -e "$(YELLOW)Running integration tests...$(RESET)"; \
	rm -f $(SRC_DIR)/*.elc; \
	$(BATCH) $(LOAD_PATH) -l $(INTEG_TESTS) \
		--eval '(ert-run-tests-batch-and-exit (quote (tag integration)))' && \
	echo -e "$(GREEN)Integration tests passed.$(RESET)"

# Run one test or a regexp of tests, for example
#   make test-one TEST=lst-refile-across-files
test-one:
	@$(BATCH) $(LOAD_PATH) $(foreach f,$(TEST_FILES),-l $(f)) \
		--eval '(ert-run-tests-batch-and-exit "$(TEST)")'

coverage.lcov: $(SRC_FILES) $(TEST_FILES) $(wildcard $(TEST_HELPER))
	@rm -f $(SRC_DIR)/*.elc coverage.lcov
	@LST_COVERAGE=1 UNDERCOVER_FORCE=true $(BATCH) $(COV_PATH) $(LOAD_PATH) \
		$(foreach f,$(TEST_FILES),-l $(f)) \
		-f ert-run-tests-batch-and-exit

coverage: coverage.lcov ## Run tests with undercover.el and print line coverage
	@awk -F'[:,]' '/^DA:/ {lf++; if ($$3 > 0) lh++} \
		END {if (lf == 0) {print "No coverage data"; exit 1} \
		printf "Line coverage: %.1f%% (%d of %d lines)\n", 100 * lh / lf, lh, lf}' coverage.lcov

coverage-html: coverage.lcov ## Generate an HTML coverage report in htmlcov/
	@command -v genhtml >/dev/null 2>&1 || { echo -e "$(RED)genhtml not found. Install lcov.$(RESET)"; exit 1; }
	@genhtml --quiet coverage.lcov --output-directory htmlcov
	@echo -e "$(GREEN)Open htmlcov/index.html in your browser.$(RESET)"

coverage-check: coverage.lcov ## Fail if line coverage is below $(COVERAGE_MIN)%
	@awk -F'[:,]' -v min=$(COVERAGE_MIN) '/^DA:/ {lf++; if ($$3 > 0) lh++} \
		END {pct = (lf ? 100 * lh / lf : 0); \
		printf "Line coverage: %.1f%% (threshold %d%%)\n", pct, min; \
		exit (pct < min)}' coverage.lcov \
		&& echo -e "$(GREEN)Coverage meets the threshold.$(RESET)" \
		|| { echo -e "$(RED)Coverage is below $(COVERAGE_MIN)%.$(RESET)"; exit 1; }

lint: lint-compile lint-checkdoc lint-package ## Byte-compile, checkdoc, and package-lint

lint-compile: compile
	@rm -f $(SRC_DIR)/*.elc

lint-checkdoc: ## Run checkdoc and fail on any warning
	@echo -e "$(YELLOW)Running checkdoc...$(RESET)"
	@out=$$($(BATCH) --eval '(checkdoc-file "$(SRC_FILES)")' 2>&1); \
	if [ -n "$$out" ]; then echo "$$out"; echo -e "$(RED)checkdoc found problems.$(RESET)"; exit 1; fi
	@echo -e "$(GREEN)checkdoc is clean.$(RESET)"

lint-package: ## Run package-lint (MELPA requirements)
	@echo -e "$(YELLOW)Running package-lint...$(RESET)"
	@[ -d $(PACKAGE_LINT_DIR) ] || { echo -e "$(RED)Run make install-test-deps first.$(RESET)"; exit 1; }
	@$(BATCH) -L $(PACKAGE_LINT_DIR) \
		--eval "(progn (require 'package) (package-initialize) (require 'package-lint))" \
		--eval '(setq package-lint-main-file "$(SRC_FILES)")' \
		-f package-lint-batch-and-exit $(SRC_FILES)
	@echo -e "$(GREEN)package-lint is clean.$(RESET)"

# --- maketests: auto-generated targets (end) ---

# --- makedocs: auto-generated targets (begin) ---

docs-deps: ## Check for the documentation tools (Emacs Org, makeinfo, pandoc)
	@echo -e "$(YELLOW)Checking documentation tools...$(RESET)"
	@$(BATCH) --eval "(require 'ox-texinfo)" && echo "  ox-texinfo: found"
	@command -v $(MAKEINFO) >/dev/null 2>&1 && echo "  makeinfo: found" || \
		echo -e "  $(RED)makeinfo: missing$(RESET) (brew install texinfo, or apt install texinfo)"
	@command -v $(PANDOC) >/dev/null 2>&1 && echo "  pandoc: found" || \
		echo -e "  $(YELLOW)pandoc: missing$(RESET) (optional, for HTML pages from Markdown)"

texi: $(TEXI_MANUAL) ## Export the Org manual to Texinfo

$(TEXI_MANUAL): $(wildcard $(ORG_MANUAL))
	@[ -f $(ORG_MANUAL) ] || { echo -e "$(RED)$(ORG_MANUAL) does not exist yet. Write the Org manual first.$(RESET)"; exit 1; }
	@echo -e "$(YELLOW)Exporting $(ORG_MANUAL) to Texinfo...$(RESET)"
	@$(BATCH) --eval "(require 'ox-texinfo)" \
		--eval '(with-current-buffer (find-file-noselect "$(ORG_MANUAL)") (org-texinfo-export-to-texinfo))'

info: $(INFO_MANUAL) ## Build the Info manual

$(INFO_MANUAL): $(TEXI_MANUAL)
	@$(MAKEINFO) --no-split $(TEXI_MANUAL) -o $(INFO_MANUAL)
	@echo -e "$(GREEN)Built $(INFO_MANUAL).  Read it with C-u C-h i $(INFO_MANUAL)$(RESET)"

html: $(TEXI_MANUAL) ## Build the HTML manual in docs/site/manual/
	@mkdir -p $(DOCS_BUILD)
	@$(MAKEINFO) --html --no-split $(TEXI_MANUAL) -o $(DOCS_BUILD)/manual.html
	@echo -e "$(GREEN)Built $(DOCS_BUILD)/manual.html$(RESET)"

docs-api: ## Regenerate the API reference from the docstrings
	@[ -f $(DOCS_DIR)/tools/build-api.el ] || { echo -e "$(RED)$(DOCS_DIR)/tools/build-api.el does not exist yet.$(RESET)"; exit 1; }
	@echo -e "$(YELLOW)Generating API reference...$(RESET)"
	@mkdir -p $(DOCS_DIR)/api $(DOCS_BUILD)
	@$(BATCH) -L $(SRC_DIR) -l $(DOCS_DIR)/tools/build-api.el \
		--eval '(lst-docs-write-api "$(API_MD)")'
	@if command -v $(PANDOC) >/dev/null 2>&1; then \
		$(PANDOC) $(API_MD) --standalone --toc --metadata title="latex-structure API" \
			-o $(DOCS_BUILD)/api.html; \
	fi
	@echo -e "$(GREEN)Wrote $(API_MD)$(RESET)"

docs: info html docs-api ## Build the Info manual, the HTML manual, and the API reference
	@if command -v $(PANDOC) >/dev/null 2>&1 && [ -f $(DOCS_DIR)/index.md ]; then \
		$(PANDOC) $(DOCS_DIR)/index.md --standalone --metadata title="latex-structure" \
			-o $(DOCS_BUILD)/index.html; \
	fi
	@if command -v $(PANDOC) >/dev/null 2>&1 && [ -f $(DOCS_DIR)/guides/getting-started.md ]; then \
		$(PANDOC) $(DOCS_DIR)/guides/getting-started.md --standalone --toc \
			--metadata title="Getting started" -o $(DOCS_BUILD)/getting-started.html; \
	fi
	@echo -e "$(GREEN)Documentation is in $(DOCS_BUILD)/ and $(INFO_MANUAL)$(RESET)"

docs-serve: docs ## Serve docs/site at http://localhost:8000
	@echo -e "$(YELLOW)Serving $(DOCS_BUILD) at http://localhost:$(DOCS_PORT) (Ctrl-C to stop)$(RESET)"
	@cd $(DOCS_BUILD) && $(PYTHON) -m http.server $(DOCS_PORT)

docs-open: docs ## Build the docs and open them in a browser
	@f=$(DOCS_BUILD)/index.html; [ -f $$f ] || f=$(DOCS_BUILD)/manual.html; \
	open $$f 2>/dev/null || xdg-open $$f 2>/dev/null || echo "Open $$f in your browser."

docs-check: ## Fail if fewer than $(DOCS_MIN)% of the symbols have docstrings
	@[ -f $(DOCS_DIR)/tools/doc-coverage.el ] || { echo -e "$(RED)$(DOCS_DIR)/tools/doc-coverage.el does not exist yet.$(RESET)"; exit 1; }
	@$(BATCH) -L $(SRC_DIR) -l $(DOCS_DIR)/tools/doc-coverage.el \
		--eval '(lst-docs-check-coverage $(DOCS_MIN))'

docs-lint: lint-checkdoc ## Run checkdoc and a strict makeinfo pass on the manual
	@[ -f $(TEXI_MANUAL) ] || { echo -e "$(YELLOW)No $(TEXI_MANUAL) yet; skipping the makeinfo pass.$(RESET)"; exit 0; }; \
	$(MAKEINFO) --no-split -o /dev/null $(TEXI_MANUAL) && \
		echo -e "$(GREEN)The manual builds cleanly.$(RESET)"

docs-clean: ## Remove generated documentation
	@rm -rf $(DOCS_BUILD) $(INFO_MANUAL)

# --- makedocs: auto-generated targets (end) ---

clean: docs-clean ## Remove byte code, coverage reports, and generated docs
	@echo -e "$(YELLOW)Cleaning...$(RESET)"
	@rm -rf *.elc $(TEST_DIR)/*.elc coverage.lcov htmlcov
	@echo -e "$(GREEN)Clean.$(RESET)"
