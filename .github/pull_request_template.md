## Summary
<!-- What does this change and why? Link related issues (Fixes #123). -->

## Checklist
- [ ] `examples/` is regenerated (`rake sqlc_generate_process`) and committed
- [ ] Tests added or updated (`rake test`, and `rake end2end_*` when the generated code changes)
- [ ] The generated code stays RuboCop-clean (`rake rubocop`) and Steep-clean (`rake steep`)
- [ ] `[release]` / `[minor]` / `[major]` in the merge commit message only if this should create a release
