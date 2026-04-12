"""Base repository abstractions.

Transaction policy
------------------
Repositories never call ``db.commit()`` or ``db.rollback()``. Services own the
unit-of-work boundary and decide when to commit. Reads return whatever the
session has visibility of; writes (``add``/``delete``) stage entities but do
not flush or commit.

Repositories migrated from the legacy ``app/crud/`` folder are an interim
exception — they preserve their original commit-on-write behavior to avoid
breaking callers in main.py / api/deps/auth.py. Those repositories will adopt
the no-commit policy in the service-rewiring bead (Uplift_App-4xc).

Lifecycle
---------
Repositories take a per-request ``Session`` via constructor. They are
constructed by the FastAPI ``Depends`` factories in ``app/repositories/__init__.py``
so their lifetime matches the request.

Generics
--------
``BaseRepository[ModelT, IDT]`` is parameterized over both the SQLAlchemy
model type and the primary-key type. Some entities use ``int`` PKs
(User, Reminder), others use UUID strings (MoodEntry, SessionAnchor).
"""
from __future__ import annotations

from typing import Generic, Iterable, List, Optional, Sequence, Type, TypeVar

from sqlalchemy.orm import Session

ModelT = TypeVar("ModelT")
IDT = TypeVar("IDT")


class BaseRepository(Generic[ModelT, IDT]):
    """Generic CRUD primitives. Subclasses provide ``model`` and override
    or extend with entity-specific queries.

    Subclasses MUST set ``model`` to the SQLAlchemy declarative class.
    """

    model: Type[ModelT]

    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, id_: IDT) -> Optional[ModelT]:
        return self.db.get(self.model, id_)

    def list(self, *, limit: Optional[int] = None, offset: int = 0) -> List[ModelT]:
        query = self.db.query(self.model)
        if offset:
            query = query.offset(offset)
        if limit is not None:
            query = query.limit(limit)
        return query.all()

    def add(self, entity: ModelT) -> ModelT:
        """Stage a new entity. Does NOT commit.

        Caller (service) must commit and may call ``db.refresh(entity)``
        to populate server-generated fields.
        """
        self.db.add(entity)
        return entity

    def add_all(self, entities: Iterable[ModelT]) -> Sequence[ModelT]:
        materialised: List[ModelT] = list(entities)
        self.db.add_all(materialised)
        return materialised

    def delete(self, entity: ModelT) -> None:
        """Stage a delete. Does NOT commit."""
        self.db.delete(entity)
