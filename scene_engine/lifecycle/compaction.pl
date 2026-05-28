:- module(compaction, [
    assert_summary/4,
    summary_exists/3
]).

:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module(tiers).

assert_summary(Scene, ProjectionName, SummaryTerm, UpToClock) :-
    inject_event(Scene,
                 summary(ProjectionName, SummaryTerm),
                 injected(author)),
    promote_to_cold(Scene, UpToClock).

summary_exists(Scene, ProjectionName, SummaryTerm) :-
    arrived(_, Scene, summary(ProjectionName, SummaryTerm), _, _).
