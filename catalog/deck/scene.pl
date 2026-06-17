:- encoding(utf8).
:- module(deck, [
    declare_deck/1,
    current_order/2,
    deck_empty/1,
    deck_size/2
]).

:- use_module('../../engine/log').
:- use_module('../../engine/clock').
:- use_module('../../engine/scenes').
:- use_module('../../engine/fixpoint').

declare_deck(Name) :-
    declare_scene(Name).

% standard_deck_rules/1 — placeholder; see module documentation.
% Call declare_scene_rule/4 directly to declare deck behaviour.
% STUB: no standard rules defined here; different games declare their own.
standard_deck_rules(_DeckScene) :- true.

current_order(DeckScene, Order) :-
    most_recent_order_event(DeckScene, Event),
    order_from_event(DeckScene, Event, Order).

most_recent_order_event(DeckScene, Event) :-
    findall(
        Clock-Term,
        ( arrived(_, DeckScene, Term, Clock, _),
          order_establishing_event(Term)
        ),
        Pairs
    ),
    Pairs \= [],
    sort(0, @>=, Pairs, [_-Event|_]).

order_establishing_event(create(_)).
order_establishing_event(draw).
order_establishing_event(shuffle).
order_establishing_event(sort).

order_from_event(_DeckScene, create(Cards), Cards) :- !.
order_from_event(DeckScene, shuffle, Reversed) :-
    !,
    previous_order(DeckScene, shuffle, Prev),
    reverse(Prev, Reversed).
order_from_event(DeckScene, sort, Sorted) :-
    !,
    previous_order(DeckScene, sort, Prev),
    msort(Prev, Sorted).
order_from_event(DeckScene, draw, Rest) :-
    previous_order(DeckScene, draw, [_Top|Rest]).
order_from_event(_DeckScene, draw, []) :-
    % Draw from empty deck — top card does not exist, result is empty.
    true.

previous_order(DeckScene, CurrentEvent, PrevOrder) :-
    arrived(_, DeckScene, CurrentEvent, CurrentClock, _),
    findall(
        Clock-Term,
        ( arrived(_, DeckScene, Term, Clock, _),
          order_establishing_event(Term),
          Clock < CurrentClock
        ),
        Pairs
    ),
    sort(0, @>=, Pairs, [_-PrevEvent|_]),
    order_from_event(DeckScene, PrevEvent, PrevOrder).

deck_empty(DeckScene) :-
    current_order(DeckScene, []).

deck_size(DeckScene, N) :-
    current_order(DeckScene, Order),
    length(Order, N).
