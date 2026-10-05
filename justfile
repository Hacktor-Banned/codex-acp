# Existing checks, executed locally by hl ci; tool output stays private.
set shell := ["bash", "-eu", "-c"]

ci:
    @echo RUN dependencies
    @if ( npm ci --ignore-scripts --no-audit --no-fund ) >/dev/null 2>&1; then echo PASS dependencies; else echo FAIL dependencies; exit 1; fi
    @echo RUN types
    @if ( npm run typecheck ) >/dev/null 2>&1; then echo PASS types; else echo FAIL types; exit 1; fi
    @echo RUN tests
    @if ( npm test ) >/dev/null 2>&1; then echo PASS tests; else echo FAIL tests; exit 1; fi
    @echo RUN build
    @if ( npm run build ) >/dev/null 2>&1; then echo PASS build; else echo FAIL build; exit 1; fi
