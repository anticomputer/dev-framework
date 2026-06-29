# Walkthrough: keeping an agent on the rails

This tiny project shows the whole loop: **define your conventions once, then let a Copilot
session implement a change while the dev-framework keeps it consistent, clean, and tested.**

The example is a dependency-free in-memory todo store
([`src/todos.py`](src/todos.py)) with a couple of tests.

## 1. Define the rails (one-time)

Three files encode "how we work here":

| File | Role |
|------|------|
| [`.dev-framework.yml`](.dev-framework.yml) | Profile + commands + where the style guide lives. Its presence activates the framework for sessions in this repo. |
| [`STYLE.md`](STYLE.md) | The conventions (use `TodoStore`, raise `KeyError` for missing ids, tests required, ruff format/lint). Injected into every session via `style_guide:`. |
| [`AGENTS.md`](AGENTS.md) | Ordinary Copilot custom instructions. The framework adds *enforcement* on top. |

```yaml
# .dev-framework.yml
profile: standard
test: pytest -q
format.py: ruff format {file}
lint.py:   ruff check {file}
style_guide: STYLE.md
```

Commit these and your whole team gets identical guardrails — no per-person setup.

## 2. Start a session

```bash
cd examples/todo-service
df            # launches copilot with the framework active (or just `copilot`, since the
              # committed .dev-framework.yml activates it)
```

At `sessionStart` the framework injects the rails into the agent's context:

```
DEV-FRAMEWORK: ACTIVE (profile: standard).
STANDARD — formatting/lint feedback is inline; the completion gate runs type-check + tests
and BLOCKS finishing while they are red; protected paths cannot be edited.
...
This repo's verification tooling:
- Tests: pytest -q
- Format-on-edit: ruff format {file}
- Lint-on-edit:   ruff check {file}
- Project style guide: read `STYLE.md` and follow it closely.

============================ DEV-FRAMEWORK CONSTITUTION ============================
... quality bar · match existing patterns · testing discipline · delegation loop ...
```

## 3. Ask for a change

> **You:** "Add the ability to delete a todo, and a `pending()` method that returns the
> todos that aren't done yet."

Here's where the rails matter — three things happen that wouldn't otherwise:

### a) It reuses existing patterns instead of inventing new ones

Prompted by the constitution's *match-existing-patterns* rule and `STYLE.md`, the agent
extends `TodoStore` rather than adding a module-level dict or a second store. Before adding
anything new it delegates a quick check:

> **pattern-guardian:** "No drift — `delete`/`pending` belong on `TodoStore`; no parallel
> state introduced."

### b) Formatting and lint are fixed as it types

The agent writes `delete()` with an unused import. The moment it saves the file, the
`postToolUse` hook runs and feeds the result straight back:

```
dev-framework — post-edit check on src/todos.py:
Lint (`ruff check src/todos.py`) found issues in src/todos.py you should fix:
src/todos.py:2:1: F401 [*] `typing.Optional` imported but unused
Address these now while the context is fresh.
```

The agent removes the import on the spot — you never see the lint noise.

### c) It can't claim "done" on unverified code

Following `STYLE.md` ("missing ids raise `KeyError`"), a test is added:

```python
def test_delete_missing_raises():
    store = TodoStore()
    with pytest.raises(KeyError):
        store.delete(999)
```

But the agent's first implementation swallows the error:

```python
def delete(self, todo_id: int) -> None:
    self._items.pop(todo_id, None)   # silently ignores missing ids — violates STYLE.md
```

The agent thinks it's finished and tries to end the session. The `agentStop` **completion
gate** runs the suite and refuses:

```
dev-framework completion gate — you cannot finish yet. The repo's checks are failing:

### Tests failed: `pytest -q` (exit 1)
FAILED tests/test_todos.py::test_delete_missing_raises - DID NOT RAISE <class 'KeyError'>

Fix the underlying cause and continue. Do NOT disable, skip, or weaken these checks to get
past the gate. (Block 1/3 this session.)
```

The agent fixes the implementation:

```python
def delete(self, todo_id: int) -> None:
    del self._items[todo_id]   # raises KeyError for a missing id, per STYLE.md
```

re-runs, the gate goes green, and only then is the task allowed to finish — with a test that
proves the behavior.

## 4. What kept it on the rails

| Safeguard | What it prevented |
|-----------|-------------------|
| `style_guide` + constitution injected at `sessionStart` | The agent knew your conventions before writing a line. |
| `pattern-guardian` + match-existing-patterns rule | A second store / divergent state (codebase drift). |
| `postToolUse` format + lint | Style and lint debt landing in the diff. |
| `agentStop` gate (`profile: standard`) | A premature "done" on code with a failing test. |

Nothing here was bespoke to this repo's tooling — point the framework at a Node, Go, Rust,
or polyglot project and the same loop runs with that stack's formatter, linter, and test
command. Set `profile: advisory` if you want all of this as *feedback* without the hard gate.
