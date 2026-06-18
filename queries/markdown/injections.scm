; Intentionally empty (no `; extends`), so it overrides nvim-treesitter's
; markdown injections.scm. That query crashes under Neovim 0.12 core treesitter
; ("attempt to call method 'range' (a nil value)"). With no injection patterns,
; markdown prose still gets Treesitter highlighting; fenced code blocks just
; aren't sub-highlighted by their language. Remove this file if you migrate
; nvim-treesitter to its `main` branch (which ships a compatible query).
