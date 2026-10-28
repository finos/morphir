from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Pending:
    pass


@dataclass(frozen=True)
class Approved:
    amount: float


type Decision = Pending | Approved

type Point = tuple[float, float]
