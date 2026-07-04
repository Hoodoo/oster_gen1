:- encoding(utf8).
:- module(repl, [start_repl/0]).

:- use_module('../engine/log').
:- use_module('../engine/clock').
:- use_module('../engine/scenes').
:- use_module('../engine/gates').
:- use_module('../engine/fixpoint').
:- use_module('../engine/probes').
:- use_module('../lifecycle/closure').
:- use_module('../projections/legal_actions').
:- use_module('../projections/why_blocked').
:- use_module('../projections/investigation').
:- use_module('../projections/post_fixpoint').
:- use_module('../verify/contracts').
:- use_module('../catalog/tavern/scene',  [declare_tavern_world/0]).
:- use_module('../catalog/tavern/gates',  [declare_tavern_gates/0]).
:- use_module('../catalog/deck/scene',    [current_order/2,
                                           deck_empty/1,
                                           deck_size/2]).
:- use_module('../catalog/warrior/scene', [current_hp/2,
                                           is_defeated/1]).

:- dynamic scene_projection/2.
:- discontiguous handle_command/1.
% scene_projection(Scene, Goal)
% Goal is called to display state for Scene.
% Registered at world-load time by register_projections/0.

register_projections :-
    % Deck projections
    forall(
        ( scenes:scene(S), arrived(_, S, create(_), _, _) ),
        assertz(scene_projection(S, repl:print_deck_state(S)))
    ),
    % Warrior projections
    forall(
        ( scenes:scene(S), arrived(_, S, created(hp(_)), _, _) ),
        assertz(scene_projection(S, repl:print_warrior_state(S)))
    ).

print_deck_state(Scene) :-
    ( current_order(Scene, Order) ->
        format("  ~w order: ~w~n", [Scene, Order]),
        deck_size(Scene, N),
        format("  ~w size: ~w~n", [Scene, N])
    ;
        format("  ~w: no order established~n", [Scene])
    ).

print_warrior_state(Scene) :-
    current_hp(Scene, HP),
    format("  ~w hp: ~w~n", [Scene, HP]),
    ( is_defeated(Scene) ->
        format("  ~w: DEFEATED~n", [Scene])
    ;
        true
    ).

load_world :-
    declare_tavern_world,
    declare_tavern_gates,
    register_projections,
    format("World loaded: tavern (patron_a, patron_b, street, window open)~n").

start_repl :-
    format("~nOster REPL — developer interface~n"),
    format("Type 'help' for commands, 'quit' to exit.~n~n"),
    load_world,
    repl_loop.

repl_loop :-
    format("oster> "),
    ( read_term(Command, [variable_names(_)]) ->
        ( Command == end_of_file ->
            format("~nGoodbye.~n")
        ;
            catch(
                handle_command(Command),
                Error,
                format("Error: ~w~n", [Error])
            ),
            repl_loop
        )
    ;
        format("Parse error — try again~n"),
        repl_loop
    ).

handle_command(quit) :- !,
    format("Goodbye.~n"),
    halt.

handle_command(help) :- !,
    print_help.

handle_command(inject(Scene, Event)) :- !,
    inject_event(Scene, Event, injected(player)),
    world_step,
    clock_value(Clock),
    format("Injected ~w into ~w at clock ~w~n", [Event, Scene, Clock]).

handle_command(inject(Scene, Event, Source)) :- !,
    inject_event(Scene, Event, injected(Source)),
    world_step,
    clock_value(Clock),
    format("Injected ~w into ~w (source: ~w) at clock ~w~n",
           [Event, Scene, Source, Clock]).

handle_command(log(Scene)) :- !,
    print_scene_log(Scene).

handle_command(state(Scene)) :- !,
    print_scene_state(Scene).

handle_command(probe(Scene)) :- !,
    probes:probe(Scene, vocab(Heads, Gates)),
    format("Vocabulary for ~w:~n", [Scene]),
    format("  Rule heads: ~w~n", [Heads]),
    format("  Outgoing gates: ~w~n", [Gates]).

handle_command(outbound(Scene, EventTerm)) :- !,
    why_blocked(Scene, EventTerm, Explanation),
    format("~w leaving ~w: ~w~n", [EventTerm, Scene, Explanation]).

handle_command(chain(EventId)) :- !,
    ( investigation_chain(EventId, Chain) ->
        format("Provenance chain for ~w:~n", [EventId]),
        forall(member(step(EId, S, T, Cause), Chain),
               format("  ~w in ~w: ~w (cause: ~w)~n", [EId, S, T, Cause]))
    ;
        format("No chain found for ~w~n", [EventId])
    ).

handle_command(verify) :- !,
    ( verify_contracts ->
        true
    ;
        format("verify_contracts failed — see output above~n")
    ).

handle_command(close(Scene)) :- !,
    clock_value(Clock),
    declare_closure(Scene, Clock),
    world_step,
    format("Declared closure for ~w at clock ~w~n", [Scene, Clock]).

handle_command(step) :- !,
    world_step,
    clock_value(Clock),
    format("World stepped to clock ~w~n", [Clock]).

handle_command(legal(Scene)) :- !,
    legal_actions(Scene, Actions),
    format("Legal actions from ~w:~n", [Scene]),
    ( Actions = [] ->
        format("  (none)~n")
    ;
        forall(member(action(GateId, Dest, Shape), Actions),
               format("  ~w → ~w: ~w~n", [GateId, Dest, Shape]))
    ).

handle_command(scenes) :- !,
    findall(Root, scene_root(Root), Roots),
    ( Roots == [] ->
        format("No scenes declared~n")
    ;
        format("Scenes:~n"),
        forall(member(Root, Roots), print_scene_node(Root, 0))
    ).

print_scene_node(Scene, Depth) :-
    Spaces is Depth * 2,
    tab(Spaces),
    format("~w~n", [Scene]),
    findall(Child, scene_parent(Child, Scene), Children),
    Depth1 is Depth + 1,
    forall(member(Child, Children), print_scene_node(Child, Depth1)).

handle_command(gates) :- !,
    findall(g(GateId, Source, Dest, Direction),
            gate(GateId, Source, Dest, Direction),
            GateList),
    ( GateList == [] ->
        format("No gates declared~n")
    ;
        format("Gates:~n"),
        forall(
            member(g(GateId, Source, Dest, Direction), GateList),
            ( ( gate_open(GateId) -> Status = open ; Status = closed ),
              format("  ~w: ~w -> ~w (~w, ~w)~n",
                     [GateId, Source, Dest, Direction, Status])
            )
        )
    ).

handle_command(summary) :- !,
    clock_value(Clock),
    post_fixpoint_summary(Clock, Changes),
    ( Changes == [] ->
        format("No changes at clock ~w~n", [Clock])
    ;
        format("Changes at clock ~w:~n", [Clock]),
        forall(member(change(Scene, Term, Cause), Changes),
               format("  ~w in ~w (cause: ~w)~n", [Term, Scene, Cause]))
    ).

handle_command(Unknown) :-
    format("Unknown command: ~w~n", [Unknown]),
    format("Type 'help' for available commands.~n").

print_help :-
    format("Commands (all require trailing period):~n"),
    format("  inject(Scene, Event)         — inject event (source: player) and step world~n"),
    format("  inject(Scene, Event, Source)  — inject event with an explicit source~n"),
    format("  log(Scene)                   — show arrived facts for scene~n"),
    format("  state(Scene)                 — show derived state for scene~n"),
    format("  probe(Scene)                 — show vocabulary surface~n"),
    format("  legal(Scene)                 — show currently legal actions~n"),
    format("  outbound(Scene, Event)        — would this event leave Scene right now, and why not~n"),
    format("  chain(EventId)                — show provenance chain~n"),
    format("  summary                       — show what changed at the current clock~n"),
    format("  scenes                        — list all scenes, hierarchically~n"),
    format("  gates                         — list all gates, flat~n"),
    format("  verify                        — run verify_contracts~n"),
    format("  close(Scene)                  — declare closure for scene~n"),
    format("  step                          — step world without injecting~n"),
    format("  quit                          — exit~n").

print_scene_log(Scene) :-
    findall(Clock-EventId-Term-Tier,
            ( arrived(EventId, Scene, Term, Clock, _),
              tier_status(EventId, Tier)
            ),
            Unsorted),
    msort(Unsorted, Sorted),
    ( Sorted = [] ->
        format("No events in ~w~n", [Scene])
    ;
        format("Log for ~w:~n", [Scene]),
        forall(
            member(Clock-EventId-Term-Tier, Sorted),
            format("  [~w] ~w ~w (~w)~n", [Clock, EventId, Term, Tier])
        )
    ).

print_scene_state(Scene) :-
    ( scene_projection(Scene, Goal) ->
        call(Goal)
    ;
        format("No state projections registered for ~w~n", [Scene]),
        format("(Use log(~w) to see raw arrived facts)~n", [Scene])
    ).
