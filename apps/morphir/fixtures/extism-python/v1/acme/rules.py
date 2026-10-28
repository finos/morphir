from __future__ import annotations

from collections.abc import Callable

from .models import Decision, Point


def choose(flag: bool, first: int, second: int) -> int:
    if flag:
        return first
    else:
        return second


def pick(flag: bool, first: Decision, second: Decision) -> Decision:
    return first if flag else second


def pair(left: float, right: float) -> Point:
    return (left, right)


def apply_twice(step: Callable[[int], int], value: int) -> int:
    return step(step(value))


def twice_identity(value: int) -> int:
    return apply_twice(lambda item: item, value)


def large_value() -> int:
    return 9007199254740993
