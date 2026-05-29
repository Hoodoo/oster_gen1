:- module(clock, [clock_value/1, advance_clock/0]).

:- dynamic clock_counter/1.
clock_counter(0).

clock_value(V) :- clock_counter(V).

advance_clock :-
    retract(clock_counter(N)),
    N1 is N + 1,
    assertz(clock_counter(N1)).
