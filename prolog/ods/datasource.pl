/*  Part of SWI-Prolog odf-sheet pack

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org/pack/list?p=odf-sheet

    Copyright (c) 2012-2014, VU University of Amsterdam
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are
    met:

    1. Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
    IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
    TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
    PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
    TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
    LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

:- module(datasource,
	  [ ds_sheet/2,			% +DS, -Sheet
	    ds_size/3,			% +DS, -Columns, -Rows
	    ds_cell_count/2,		% +DS, -Cells
	    ds_empty/1,			% +DS
	    ds_side/3,			% ?Side, ?DS, ?RowCol
	    ds_id/2,			% ?DS, ?Id
	    ds_id/3,			% ?DS, ?Id, ?Type

	    ds_inside/3,		% +DS, ?X, ?Y
	    ds_adjacent/3,		% +DS1, ?Rel, +DS2

	    ds_intersection/3,		% +DS1, +DS2, -DS
	    ds_union/3,			% +DS1, +DS2, -DS
	    ds_union/2,			% +DSList, -DS
	    ds_intersections/2,		% +DSList, -Pairs
	    ds_subtract/3,		% +Subtract, +From, -DSList
	    ds_row_slice/3,		% +DS1, ?Offset, ?Slice
	    ds_row_slice/4,		% +DS1, ?Offset, ?Height, ?Slice
	    ds_unbounded_row_slice/3,	% +DS1, +Offset, ?Slice
	    ds_column_slice/3,		% +DS1, ?Offset, ?Slice
	    ds_column_slice/4,		% +DS1, ?Offset, ?Width, ?Slice
	    ds_unbounded_column_slice/3,% +DS1, +Offset, ?Slice
	    ds_grow/3			% +DS0, +Offset, -DS
	  ]).
:- use_module(table).
:- use_module(library(apply)).

/** <module> Represent and reason about sheet areas

This module represents rectangular areas in a sheet and can reason about
such regions.
*/


		 /*******************************
		 *	 SIMPLE PROPERTIES	*
		 *******************************/

%%	ds_sheet(+DS, -Sheet) is det.
%
%	True when DS is on Sheet.

ds_sheet(cell_range(Sheet, _,_, _,_), Sheet).

%%	ds_size(+DS, -Columns, -Rows) is det.
%
%	True when Columns and Rows represent the size of a datasource

ds_size(cell_range(_Sheet, SX,SY, EX,EY), Columns, Rows) :-
	Columns is EX-SX+1,
	Rows is EY-SY+1.

%%	ds_cell_count(+DS, -Count) is det.
%
%	True when Count is the number of cells in DS.

ds_cell_count(cell_range(_Sheet, SX,SY, EX,EY), Cells) :-
	Columns is EX-SX+1,
	Rows is EY-SY+1,
	Cells is Rows*Columns.

%%	ds_side(?Which, ?DS, ?Value)
%
%	True when Value is the row/column of   the indicated side of the
%	datasource. Which is one of =left=, =right=, =top= or =bottom=.

ds_side(left,   cell_range(_Sheet, SX,_SY, _EX,_EY), SX).
ds_side(right,  cell_range(_Sheet, _SX,_SY, EX,_EY), EX).
ds_side(top,    cell_range(_Sheet, _SX,SY, _EX,_EY), SY).
ds_side(bottom, cell_range(_Sheet, _SX,_SY, _EX,EY), EY).

%%	ds_empty(+DS) is semidet.
%
%	True if DS is empty (contains no cells)

ds_empty(cell_range(_Sheet, SX,SY, EX,EY)) :-
	(   EX < SX
	->  true
	;   EY < SY
	).

%%	ds_id(+DS, -ID) is det.
%%	ds_id(-DS, +ID) is det.
%
%	True when ID is an identifier for DS

ds_id(DS, Id) :-
	ds_id(DS, Id, _).

ds_id(DS, Id, Type) :-
	ground(DS), !,
	DS = cell_range(Sheet, SX,SY, EX,EY),
	column_name(SX, SC),
	column_name(EX, EC),
	(   var(Type)
	->  Prefix = ''
	;   type_prefix(Type, Prefix)
	),
	(   sheet_name_need_quotes(Sheet)
	->  format(atom(Id), '~w[\'~w\'.~w~w:~w~w]', [Prefix,Sheet,SC,SY,EC,EY])
	;   format(atom(Id), '~w[~w.~w~w:~w~w]', [Prefix,Sheet,SC,SY,EC,EY])
	).
ds_id(DS, Id, Type) :-
	type_prefix(Prefix, Type),
	sub_atom(Id, 0, 1, _, Prefix),
	sub_atom(Id, 1, 1, _, '['),
	sub_atom(Id, 1, _, 0, DSID),
	atom_codes(DSID, Codes),
	phrase(ods_reference(DS, ''), Codes).

type_prefix(block, 'B').
type_prefix(table, 'T').


		 /*******************************
		 *	    COORDINATES		*
		 *******************************/

%%	ds_inside(+DS, ?X, ?Y) is nondet.
%
%	True when X,Y is inside the datasource

ds_inside(cell_range(_Sheet, SX,SY, EX,EY), X, Y) :-
	between(SY, EY, Y),
	between(SX, EX, X).


		 /*******************************
		 *	 SPATIAL RELATIONS	*
		 *******************************/

%%	ds_adjacent(+DS1, -Rel, +DS2) is semidet.
%
%	True if DS1 is =above=, =below= =left_of= or =right_of= DS2.

ds_adjacent(cell_range(Sheet, SX1,SY1, EX1,EY1),
	    Rel,
	    cell_range(Sheet, SX2,SY2, EX2,EY2)) :-
	(   range_intersect(SY1,EY1, SY2,EY2, _,_)
	->  (   EX1+1 =:= SX2
	    ->  Rel = left_of
	    ;	EX2+1 =:= SX1
	    ->	Rel = right_of
	    )
	;   range_intersect(SX1,EX1, SX2,EX2, _,_)
	->  (   EY1+1 =:= SY2
	    ->  Rel = above
	    ;	EY2+1 =:= SY1
	    ->	Rel = below
	    )
	).



		 /*******************************
		 *	     SET LOGIC		*
		 *******************************/

%%	ds_intersection(+DS1, +DS2, -DS) is semidet.
%
%	True when the intersection of DS1 and DS2 is DS.  Fails if the
%	two do not intersect.

ds_intersection(cell_range(Sheet, SX1,SY1, EX1,EY1),
		cell_range(Sheet, SX2,SY2, EX2,EY2),
		cell_range(Sheet, SX,SY, EX,EY)) :-
	range_intersect(SX1,EX1, SX2,EX2, SX,EX),
	range_intersect(SY1,EY1, SY2,EY2, SY,EY).

range_intersect(S1,E1, S2,E2, S,E) :-
	S is max(S1,S2),
	E is min(E1,E2),
	S =< E.


%%	ds_union(+DS1, +DS2, -DS) is det.
%
%	True when the union of DS1 and DS2 is DS.

ds_union(cell_range(Sheet, SX1,SY1, EX1,EY1),
	 cell_range(Sheet, SX2,SY2, EX2,EY2),
	 cell_range(Sheet, SX,SY, EX,EY)) :-
	range_union(SX1,EX1, SX2,EX2, SX,EX),
	range_union(SY1,EY1, SY2,EY2, SY,EY).

range_union(S1,E1, S2,E2, S,E) :-
	S is min(S1,S2),
	E is max(E1,E2).


%%	ds_union(+DSList, -DS) is det.
%
%	True when DS is the union of all datasources

ds_union([], cell_range(_, 0,0,0,0)).
ds_union([H|T], Union) :-
	ds_union_list(T, H, Union).

ds_union_list([], DS, DS).
ds_union_list([H|T], DS0, DS) :-
	ds_union(H, DS0, DS1),
	ds_union_list(T, DS1, DS).


%%	ds_intersections(+ListOfDS, -Pairs) is semidet.
%
%	True when Pairs is a non-empty list of pairs of datasources with
%	a non-empty intersection.
%
%	@tbd	Can be more efficient

ds_intersections(ListOfDS, Pairs) :-
	findall(A-B,
		( member(A,ListOfDS),
		  member(B,ListOfDS),
		  A@>B,
		  ds_intersection(A,B,_)
		),
		Pairs),
	Pairs \== [].

%%	ds_subtract(+Subtract, +From,
%%		    -Remainder:list(pair(where-datasource))) is det.
%
%	Remainder is a list of pairs   of the form <location>-datasource
%	that describes the area of From that is not covered by Subtract.
%	Defined locations are:
%
%	  $ =all= :
%	  From is unaffected
%	  $ =top= and =bottom= :
%	  Subtract removes a set of rows
%	  $ =left= and =right= :
%	  Subtract removes a set of columns
%	  $ =|top/left|=, =|top/middle|=, =|top/right|=, =|middle/left|=,
%	  =|middle/right|=, =|bottom/left|=, =|bottom/middle|=
%	  and =|bottom/right|= :
%	  Subtract is enclosed in From
%
%	Empty datasources are removed from  the   result  set.  E.g., if
%	Subtract removes the top N rows  of   From,  Remainder is a list
%	holding only =|bottom - DSRem|=.

ds_subtract(Subtract, From, Remainder) :-
	ds_intersection(Subtract, From, I), !,
	ds_subtract_i(From, I, Remainder).
ds_subtract(_, From, [all-From]).	% no intersection: From is unaffected

ds_subtract_i(DS, DS, Remainder) :- !,
	Remainder = [].			% DS1 is entirely enclosed by DS2
ds_subtract_i(cell_range(Sheet, SX,SY, EX,EY),
	      cell_range(Sheet, SX,Sy, EX,Ey),
	      Remainder) :- !,
	Sy1 is Sy-1,
	Ey1 is Ey+1,
	Rem0 = [ top    - cell_range(Sheet, SX, SY,  EX, Sy1),  % top
		 bottom - cell_range(Sheet, SX, Ey1, EX, EY)    % bottom
	       ],
	exclude(empty_value, Rem0, Remainder).
ds_subtract_i(cell_range(Sheet, SX,SY, EX,EY),
	      cell_range(Sheet, Sx,SY, Ex,EY),
	      Remainder) :- !,
	Sx1 is Sx-1,
	Ex1 is Ex+1,
	Rem0 = [ left  - cell_range(Sheet, SX,  SY, Sx1, EY),  % left
		 right - cell_range(Sheet, Ex1, SY, EX, EY)    % right
	       ],
	exclude(empty_value, Rem0, Remainder).
ds_subtract_i(cell_range(Sheet, SX,SY, EX,EY),
	      cell_range(Sheet, Sx,Sy, Ex,Ey),
	      Remainder) :-
	Sx1 is Sx-1, Sy1 is Sy-1,
	Ex1 is Ex+1, Ey1 is Ey+1,
	Rem0 = [ top/left      - cell_range(Sheet, SX,   SY, Sx1, Sy1),
		 top/middle    - cell_range(Sheet, Sx,   SY,  Ex, Sy1),
		 top/right     - cell_range(Sheet, Ex1,  SY,  EX, Sy1),
		 middle/left   - cell_range(Sheet, SX,   Sy, Sx1,  Ey),
		 middle/right  - cell_range(Sheet, Ex1,  Sy,  EX,  Ey),
		 bottom/left   - cell_range(Sheet, SX,  Ey1, Sx1,  EY),
		 bottom/middle - cell_range(Sheet, Sx,  Ey1,  Ex,  EY),
		 bottom/right  - cell_range(Sheet, Ex1, Ey1,  EX,  EY)
	       ],
	exclude(empty_value, Rem0, Remainder).

empty_value(_-DS) :-
	ds_empty(DS).


		 /*******************************
		 *	      SLICING		*
		 *******************************/

%%	ds_row_slice(+DS, ?Offset, ?Slice) is det.
%
%	True when Slice is a row from   DS at offset Offset. Offsets are
%	0-based.

ds_row_slice(cell_range(Sheet, SX,SY, EX,EY), Offset,
	     cell_range(Sheet, SX,RY, EX,RY)) :-
	H is EY-SY,
	between(0,H,Offset),
	RY is SY+Offset.


%%	ds_unbounded_row_slice(+DS, +Offset, -Slice) is det.
%
%	True when Slice is a row from   DS at offset Offset. Offsets are
%	0-based. It is allowed for Slice to  be outside the range of the
%	datasouce.

ds_unbounded_row_slice(cell_range(Sheet, SX,SY, EX,_), Offset,
	     cell_range(Sheet, SX,RY, EX,RY)) :-
	RY is SY+Offset.

%%	ds_column_slice(+DS, ?Offset, ?Slice) is det.
%
%	True when Slice is a column from   DS  at offset Offset. Offsets
%	are 0-based.

ds_column_slice(cell_range(Sheet, SX,SY, EX,EY), Offset,
		cell_range(Sheet, CX,SY, CX,EY)) :-
	W is EX-SX,
	between(0,W,Offset),
	CX is SX+Offset.

%%	ds_row_slice(+DS, +Offset, +Height, -Slice) is det.
%
%	True when Slice is  a  horizontal   slice  from  DS, starting at
%	Offset (0-based, relative to DS) and being rows high.

ds_row_slice(cell_range(Sheet, SX,SY, EX,EY), Offset, Height,
	     cell_range(Sheet, SX,CY, EX,ZY)) :-
	Height >= 0,
	H is EY-SY,
	between(0,H,Offset),
	CY is SY+Offset,
	ZY is CY+Height-1,
	ZY =< EY.

%%	ds_column_slice(+DS, +Offset, +Width, -Slice) is det.
%
%	True when Slice is a vertical slice from DS, starting at Offset
%	(0-based, relative to DS) and being Columns wide.

ds_column_slice(cell_range(Sheet, SX,SY, EX,EY), Offset, Width,
		cell_range(Sheet, CX,SY, ZX,EY)) :-
	Width >= 0,
	W is EX-SX,
	between(0,W,Offset),
	CX is SX+Offset,
	ZX is CX+Width-1,
	ZX =< EX.

%%	ds_unbounded_column_slice(+DS, +Offset, -Slice) is det.
%
%	True when Slice is a column from   DS at offset Offset. Offsets are
%	0-based. It is allowed for Slice to  be outside the range of the
%	datasouce.

ds_unbounded_column_slice(cell_range(Sheet, SX,SY,  _,EY), Offset,
			  cell_range(Sheet, CX,SY, CX,EY)) :-
	CX is SX+Offset.

%%	ds_grow(+DS0, +Amount, -DS)

ds_grow(cell_range(Sheet, SX0,SY0, EX0,EY0),
	Offset,
	cell_range(Sheet, SX,SY, EX,EY)) :-
	SX is SX0-Offset,
	SY is SY0-Offset,
	EX is EX0+Offset,
	EY is EY0+Offset.
