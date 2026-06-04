# 04 Execution Protocol

Executor loop:

1. Inspect current repo state.
2. Read the source-of-truth chain.
3. Pick the smallest useful implementation step from the active brief.
4. Edit only required files.
5. Run focused validation.
6. Run broader validation when risk justifies it.
7. Write a session log with files changed, validation, evidence, blockers, and
   next suggested step.
8. Commit scoped files with exact git add paths.

Do not claim completion without evidence. If blocked, preserve the blocker in a
session log and commit the log if it is useful context for the reviewer.

