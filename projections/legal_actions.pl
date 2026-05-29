:- module(legal_actions, [legal_actions/2]).

:- use_module('../engine/gates').
:- use_module('../engine/probes').

legal_actions(Scene, Actions) :-
    findall(
        action(GateId, DestScene, EventShape),
        (   gate(GateId, Scene, DestScene, _),
            gate_open(GateId),
            probe(DestScene, vocab(RuleHeads, _)),
            member(EventShape, RuleHeads)
        ),
        Actions
    ).
