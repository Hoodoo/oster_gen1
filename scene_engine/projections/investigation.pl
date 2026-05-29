:- module(investigation, [investigation_chain/2, chain_root/2]).

:- use_module('../engine/log').
:- use_module('../engine/provenance').

investigation_chain(EventId, Chain) :-
    arrived(EventId, Scene, Term, _Clock, _),
    provenance_chain(EventId, ProvenanceSteps),
    enrich_chain(ProvenanceSteps, Scene, Term, Chain).

enrich_chain([], _Scene, _Term, []).
enrich_chain([step(EId, Cause)|Rest], _Scene, _Term, [step(EId, S, T, Cause)|Enriched]) :-
    ( arrived(EId, S, T, _, _) -> true ; S = unknown, T = unknown ),
    enrich_chain(Rest, _, _, Enriched).

chain_root(EventId, RootEventId) :-
    investigation_chain(EventId, Chain),
    last(Chain, step(RootEventId, _, _, _)).
