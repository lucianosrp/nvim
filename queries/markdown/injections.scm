; Authoritative (no `; extends`): replaces nvim-treesitter's bundled markdown
; injections.scm, whose full query crashes under Neovim 0.12 core treesitter.
; We keep only the two safe, high-value injections:
;   1. sub-highlight fenced code blocks by their language (```python, ```lua, …)
;   2. parse inline spans with markdown_inline (bold/italic/links/code spans)
; markdown_inline's OWN injections stay disabled (queries/markdown_inline/
; injections.scm is empty) — that's where the 0.12 crash actually lives.

((fenced_code_block
  (info_string (language) @injection.language)
  (code_fence_content) @injection.content))

((inline) @injection.content
 (#set! injection.language "markdown_inline"))
