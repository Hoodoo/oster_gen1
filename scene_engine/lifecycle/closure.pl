:- module(closure, [
    declare_closure/2,
    scene_closed/2
]).

:- use_module('../engine/log').
:- use_module('../engine/clock').

declare_closure(Scene, Clock) :-
    inject_event(Scene, closed(Scene, clock(Clock)), injected(author)).

scene_closed(Scene, Clock) :-
    arrived(_, Scene, closed(Scene, clock(Clock)), _, _).
