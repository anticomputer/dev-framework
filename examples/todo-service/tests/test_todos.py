from src.todos import TodoStore


def test_add_assigns_incrementing_ids():
    store = TodoStore()
    first = store.add("write docs")
    second = store.add("ship it")
    assert (first.id, second.id) == (1, 2)


def test_complete_marks_done():
    store = TodoStore()
    todo = store.add("review PR")
    assert store.complete(todo.id).done is True
