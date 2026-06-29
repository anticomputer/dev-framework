# Conventions — todo-service

These are the rails. The dev-framework injects this file into every active session (via
`style_guide:` in `.dev-framework.yml`) and the `pattern-guardian` / `style-enforcer`
agents check changes against it.

## Architecture
- All todo operations go through the single `TodoStore` in `src/todos.py`.
  **Do not** add parallel stores, module-level globals, or a second way to hold state.
- Keep the package dependency-free (standard library only).

## API conventions
- Public methods return a `Todo` (or a `list[Todo]`), never raw dicts.
- Missing ids raise `KeyError` — never return `None` for a not-found todo.
- Ids are assigned by the store and increment from 1; callers never set ids.

## Testing
- Every behavioral change ships with a test in `tests/` that **fails without** the change.
- Run the suite with `pytest -q`.

## Style
- Format with `ruff format`; lint with `ruff check`. No lint warnings in changed files.
- Type-hint public methods.
