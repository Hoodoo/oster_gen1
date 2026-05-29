:- module(contracts, [
    verify_contracts/0,
    check_no_self_generating_rules/0,
    check_consequence_specificity/0,
    check_provenance_acyclic/0,
    check_rule_conditions_safe/1,
    default_safe_predicates/1,
    term_contains_functor/2,
    collect_calls/2,
    run_check/2
]).

:- use_module('../engine/log').
:- use_module('../engine/scenes').
:- use_module('../engine/gates').
:- use_module('../engine/provenance').
:- use_module('../engine/fixpoint').

verify_contracts :-
    run_check('no self-generating rules',  check_no_self_generating_rules),
    run_check('consequence specificity',   check_consequence_specificity),
    run_check('provenance acyclic',        check_provenance_acyclic),
    run_check('rule conditions safe',
              check_rule_conditions_safe(default_safe_predicates)),
    format("verify_contracts: all checks passed~n").

run_check(Name, Goal) :-
    ( call(Goal) ->
        format("  [ok] ~w~n", [Name])
    ;
        format("  [FAIL] ~w~n", [Name]),
        fail
    ).

check_no_self_generating_rules :-
    \+ (
        scenes:scene_rule(RuleId, _Scene, Conditions, Template),
        functor(Template, F, _),
        term_contains_functor(Conditions, F),
        format("  rule ~w: consequence functor '~w' appears in conditions~n",
               [RuleId, F])
    ).

% DECISION: added nonvar guard on first clause — conditions may contain unbound
% variables (anonymous vars in asserted facts), and functor/3 throws on unbound.
term_contains_functor(Term, F) :-
    nonvar(Term),
    functor(Term, F, _), !.
term_contains_functor(Term, F) :-
    compound(Term),
    Term =.. [_|Args],
    member(Arg, Args),
    term_contains_functor(Arg, F).

check_consequence_specificity :-
    % Warning only — not a hard failure.
    forall(
        scenes:scene_rule(RuleId, _Scene, _Conditions, Template),
        ( ( atomic(Template), \+ is_list(Template) ) ->
            format("  warning: rule ~w has atomic consequence '~w' (consider structured term)~n", [RuleId, Template])
        ;
            true
        )
    ).

check_provenance_acyclic :-
    \+ (
        log:arrived(EventId, _, _, _, _),
        \+ provenance:provenance_acyclic(EventId),
        format("  cyclic provenance chain from event ~w~n", [EventId])
    ).

% DECISION: AllowedPreds is a predicate name (e.g. default_safe_predicates)
% called to retrieve the allowed list; the spec shows member(F/A, AllowedPreds)
% as if AllowedPreds is a list, but verify_contracts passes the predicate name.
% Calling AllowedPreds as a goal with one argument resolves this consistently.
check_rule_conditions_safe(AllowedPredsPred) :-
    call(AllowedPredsPred, AllowedPreds),
    \+ (
        scenes:scene_rule(RuleId, _Scene, Conditions, _Template),
        collect_calls(Conditions, Calls),
        member(Call, Calls),
        functor(Call, F, A),
        \+ member(F/A, AllowedPreds),
        format("  rule ~w calls unsafe predicate ~w/~w~n", [RuleId, F, A])
    ).

% DECISION: operator names quoted to avoid syntax errors in list context —
% SWI-Prolog treats bare operators as needing operands when parsed as terms.
default_safe_predicates([
    arrived/5, arrived_key/4, tier_status/2,
    caused_by/2, scene/1, scene_parent/2, scene_rule/4,
    gate/4, gate_condition/2, gate_open/1,
    is/2, '=:='/2, '=\\='/2, '<'/2, '>'/2, '=<'/2, '>='/2,
    '='/2, '\\='/2, '=='/2, '\\=='/2,
    true/0, fail/0, not/1, '\\+'/1,
    ','/2, ';'/2, '->'/2,
    member/2, memberchk/2, findall/3, aggregate_all/3,
    functor/3, arg/3, '=..'/2, ground/1, atomic/1, compound/1,
    atom/1, number/1, integer/1, is_list/1, length/2,
    format/2, write/1, nl/0
]).

collect_calls(Goal, [Goal]) :-
    ( atomic(Goal) ; var(Goal) ), !.
collect_calls((A, B), Calls) :-
    !,
    collect_calls(A, CA),
    collect_calls(B, CB),
    append(CA, CB, Calls).
collect_calls((A ; B), Calls) :-
    !,
    collect_calls(A, CA),
    collect_calls(B, CB),
    append(CA, CB, Calls).
collect_calls((A -> B), Calls) :-
    !,
    collect_calls(A, CA),
    collect_calls(B, CB),
    append(CA, CB, Calls).
collect_calls(\+(A), Calls) :-
    !, collect_calls(A, Calls).
collect_calls(Goal, [Goal]).
