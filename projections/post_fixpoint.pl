:- module(post_fixpoint, [post_fixpoint_summary/2]).

:- use_module('../engine/log').
:- use_module('../engine/provenance').

post_fixpoint_summary(Clock, Summary) :-
    findall(
        change(Scene, Term, Cause),
        (   arrived(EventId, Scene, Term, Clock, _),
            tier_status(EventId, hot),
            caused_by(EventId, Cause)
        ),
        Unsorted
    ),
    msort(Unsorted, Summary).
