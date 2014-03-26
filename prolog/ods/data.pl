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

:- module(ods_data,
	  [ assert_table/1,		% +Table
	    assert_block/1,		% +Block
	    retract_block/1,		% +BlockId

	    sheet_object/3,		% ?Sheet, ?Type, ?Object
	    object_union/2,		% ?Object, ?Union
	    object_id/2,		% ?Object, ?Id
	    object_data_type/2,		% ?Object, ?Type

	    assert_object_property/2,	% :ObjId, +Property

	    assert_cell_property/4,	% :Sheet, +X, +Y, ?Property
	    cell_property/4,		% :Sheet, ?X, ?Y, ?Property

	    assert_label/2,		% :Label, +Count

	    clean_data/0
	  ]).
:- use_module(library(error)).
:- use_module(datasource).

:- meta_predicate
	assert_table(:),
	assert_block(:),
	retract_block(:),
	sheet_object(:, ?, ?),
	assert_object_property(:, +),
	assert_cell_property(:, +, +, +),
	cell_property(:,?,?,?),
	assert_label(:,+).

:- module_transparent
	clean_data/0.


/** <module> Data store module

Defined relations:

  * table(TableId, Type, DataDS, HeaderDSList, UnionDS)
  * block(BlockId, Type, DataDS)
  * object_property(ObjectId, Property)
  * cell_property(Sheet, X, Y, Property)
*/

data(object_property/2).
data(cell_property/3).
data(table/5).
data(block/3).
data(label/2).

clean_data :-
	context_module(M),
	forall(ods_data:data(Name/Arity),
	       ( functor(Head, Name, Arity),
		 retractall(M:Head)
	       )).


		 /*******************************
		 *	       TABLES		*
		 *******************************/

%%	assert_table(:Table) is det.
%
%	@param Table is table(TableId, _Type, _MainDS, _HdrDS, Union)

assert_table(M:T) :-
	assertz(M:T),
	T = table(TabId, _Type, _MainDS, _HdrDS, Union),
	ds_sheet(Union, Sheet),
	forall(ds_inside(Union, X, Y),
	       assert_cell_property(M:Sheet, X, Y, table(TabId))).

%%	assert_block(:Block) is det.
%
%	@param Block is block(BlockId, Type, DS)

assert_block(M:T) :-
	assertz(M:T),
	T = block(BlockId, _Type, DS),
	ds_sheet(DS, Sheet),
	forall(ds_inside(DS, X, Y),
	       assert_cell_property(M:Sheet, X, Y, block(BlockId))).

%%	retract_block(:BlockId) is det.

retract_block(M:BlockId) :-
	must_be(atom, BlockId),
	retract(M:block(BlockId, _, _)), !.
retract_block(M:BlockId) :-
	existence_error(block, M:BlockId).

%%	sheet_object(:Sheet, ?Type, ?Object)
%
%	True when Sheet contains Object.  Object is a table or block
%
%	  ==
%	  table(TabId, Type, DataDS, HeaderDSList, UnionDS)
%	  ==

sheet_object(M:Sheet, table, table(TabId, Type, DataDS, HdrDS, Union)) :-
	ds_sheet(DataDS, Sheet),
	M:table(TabId, Type, DataDS, HdrDS, Union).
sheet_object(M:Sheet, block, block(BlockId, Type, DataDS)) :-
	ds_sheet(DataDS, Sheet),
	M:block(BlockId, Type, DataDS).

%%	object_union(+Object, -Union) is det.
%
%	True if Union is the UnionDS of Object.

object_union(table(_TableId, _Type, _DataDS, _HdrDS, Union), Union).
object_union(block(_BlockId, _Type, DataDS), DataDS).

%%	object_id(+Object, -Id) is det.

object_id(table(TableId, _Type, _DataDS, _HdrDS, _Union), TableId).
object_id(block(BlockId, _Type, _DataDS), BlockId).

%%	object_data_type(+Object, -Type) is det.

object_data_type(table(_TableId, Type, _DataDS, _HdrDS, _Union), Type).
object_data_type(block(_BlockId, Type, _DataDS), Type).

%%	assert_object_property(:ObjId, +Property)

assert_object_property(M:ObjId, Property) :-
	(   M:object_property(ObjId, Property)
	->  true
	;   assertz(M:object_property(ObjId, Property))
	).


		 /*******************************
		 *	       CELLS		*
		 *******************************/

%%	assert_cell_property(:Sheet, +X, +Y, +Property) is det.
%
%	Add a property to a  cell.  Does   nothing  if  the  property is
%	already defined.

assert_cell_property(M:Sheet, X, Y, Property) :-
	cell_id(X,Y,CellId),
	assertz(M:cell_property(Sheet,CellId,Property)).


%%	cell_property(:Sheet, ?X, ?Y, ?Property)
%
%	Query (inferred) properties of the cell Sheet.XY.

cell_property(M:Sheet, X, Y, Property) :-
	(   nonvar(X), nonvar(Y)
	->  cell_id(X,Y,Id),
	    M:cell_property(Sheet,Id,Property)
	;   M:cell_property(Sheet,Id,Property),
	    cell_id(X,Y,Id)
	).


		 /*******************************
		 *	       LABELS		*
		 *******************************/

%%	assert_label(:Label, +Count) is det.
%
%	Assert to label/2

assert_label(M:Label, Count) :-
	assertz(M:label(Label, Count)).
