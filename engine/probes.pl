:- module(probes, [probe/2, probe_reachable/2, probe_vocabulary/2, probe_gates/2]).

:- use_module(scenes).
:- use_module(gates).

probe(Scene, vocab(RuleHeads, OutgoingGates)) :-
    findall(Template,
            scene_rule(_, Scene, _, Template),
            RuleHeads),
    findall(gate_info(GateId, DestScene, Direction),
            gate(GateId, Scene, DestScene, Direction),
            OutgoingGates).

probe_reachable(Scene, EventShape) :-
    probe(Scene, vocab(RuleHeads, OutgoingGates)),
    (   member(Template, RuleHeads),
        \+ \+ EventShape = Template
    ;   member(gate_info(_, _, _), OutgoingGates),
        true
    ).

probe_vocabulary(Scene, Templates) :-
    probe(Scene, vocab(Templates, _)).

probe_gates(Scene, GateInfos) :-
    probe(Scene, vocab(_, GateInfos)).
