"""In-memory todo store. The single source of truth for todo state (see STYLE.md)."""
from dataclasses import dataclass


@dataclass
class Todo:
    id: int
    title: str
    done: bool = False


class TodoStore:
    """Holds todos in memory and assigns incrementing ids."""

    def __init__(self) -> None:
        self._items: dict[int, Todo] = {}
        self._next_id = 1

    def add(self, title: str) -> Todo:
        todo = Todo(id=self._next_id, title=title)
        self._items[todo.id] = todo
        self._next_id += 1
        return todo

    def complete(self, todo_id: int) -> Todo:
        todo = self._items[todo_id]  # raises KeyError for a missing id, per STYLE.md
        todo.done = True
        return todo

    def list(self) -> list[Todo]:
        return list(self._items.values())
