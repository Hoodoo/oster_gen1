:- module(provenance, [
    caused_by/2,
    assert_provenance/2,
    provenance_chain/2,
    provenance_acyclic/1
]).

:- dynamic caused_by/2.
% caused_by(EventId, Cause)
%
% Cause is one of:
%   injected(player)
%   injected(author)
%   rule(Scene, RuleId)
%   gate(GateId)
%   simulation_boundary(SimId)

assert_provenance(EventId, Cause) :-
    assertz(caused_by(EventId, Cause)).

% STUB: Session 4 will extend provenance_chain/2 to traverse multi-hop chains.
% Currently returns single-step provenance only.
provenance_chain(EventId, Chain) :-
    provenance_chain_(EventId, [EventId], Chain).

provenance_chain_(EventId, _Visited, Chain) :-
    caused_by(EventId, Cause),
    ( Cause = injected(_) ->
        Chain = [step(EventId, Cause)]
    ; Cause = simulation_boundary(_) ->
        Chain = [step(EventId, Cause)]
    ; Cause = rule(_, _) ->
        Chain = [step(EventId, Cause)]
    ; Cause = gate(_) ->
        Chain = [step(EventId, Cause)]
    ;
        Chain = [step(EventId, Cause)]
    ).

provenance_acyclic(EventId) :-
    provenance_acyclic_(EventId, []).

provenance_acyclic_(EventId, Visited) :-
    \+ member(EventId, Visited),
    ( caused_by(EventId, injected(_)) -> true
    ; caused_by(EventId, simulation_boundary(_)) -> true
    ; caused_by(EventId, Cause),
      ( Cause = rule(_, _) -> true
      ; Cause = gate(_) -> true
      ; true
      )
    ).
