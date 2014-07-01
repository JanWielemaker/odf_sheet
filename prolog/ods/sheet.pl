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

:- module(ods_sheet,
	  [ ods_load/1,			% :File
	    ods_current/1,		% :URL
	    ods_unload/0,
	    ods_unload_all/0,
	    ods_compile/0,
	    ods_compile_all/0,
	    ods_eval/2,			% +Expression, -Value
	    ods_style_property/2,	% :Style, ?Property
	    cell_value/4,		% :Sheet, ?X, ?Y, ?Value
	    cell_type/4,		% :Sheet, ?X, ?Y, ?Type
	    cell_formula/4,		% :Sheet, ?X, ?Y, ?Formula
	    cell_eval/4,		% :Sheet, ?X, ?Y, -Value
	    cell_style/4,		% :Sheet, ?X, ?Y, ?Property
	    cell/8,			% :Sheet, ?X, ?Y, ?V, ?T, ?F, ?S, ?A

	    column_name/2,		% ?Index, ?Name
	    ods_DOM/3,			% :Source, -DOM, +Options

	    cell_id/3,			% ?X, ?Y, ?Id

	    sheet_name_need_quotes/1,	% +SheetName
	    ods_reference//2		% -Expr, +Table
	  ]).
:- use_module(library(xpath)).
:- use_module(library(sgml)).
:- use_module(library(uri)).
:- use_module(library(archive)).
:- use_module(library(apply_macros)).
:- use_module(library(lists)).
:- use_module(library(dcg/basics)).
:- use_module(library(aggregate)).
:- use_module(functions).
:- use_module(bisect).

:- set_prolog_flag(optimise, true).

/** <module> Load Open Document Spreadsheets

This module loads an Open Document spreadsheet into the Prolog database.
The primary call is ods_load/1, which adds  the following facts into the
calling module:

    * sheet(Sheet, Style)
    * col(Sheet, X, Style)
    * row(Sheet, Y, Style)
    * cell(Sheet, Id, Value, Type, Formula, Style, Annotation)
    * span(Id, IdBase)
    * style(Name, XMLDOM)

In addition, it provides  the   following  high-level  query primitives:
cell_value/4, cell_type/4, cell_formula/4, cell_eval/4 and cell_style/4.
All these predicates use the same calling convention, e.g.,

    ==
    cell_value(Sheet, X, Y, Value)
    ==

where Sheet is the name of the sheet, X is the column (an integer) and Y
is the row (an  integer).  Value  is   the  current  value  of the cell.
Although integer columns are easier for computation, these predicates do
allow specifying the column  as  an  atom.   E.g.,  the  value  of  cell
=|WindOffshore.D43|= can be requested using  the   call  below.  This is
mainly intended for querying from the toplevel.

    ==
    ?- cell_value('WindOffshore', d, 43, X).
    X = 0.07629.
    ==

Values are represented using the following conventions:

    * Textual values are represented using an atom
    * Numerical values are represented using Prolog numbers
    * Booleans are represented as @true or @false
    * Errors are representated as #(Error)

@tbd	Add interface to query cell spanning
@tbd	Correctly report cell boolean and error values.
*/

:- meta_predicate
	ods_load(:),
	ods_current(:),
	ods_eval(:, -),
	ods_style_property(:, ?),
	cell_value(:, ?, ?, ?),
	cell_type(:, ?, ?, ?),
	cell_formula(:, ?, ?, ?),
	cell_eval(:, ?, ?, ?),
	cell_style(:, ?, ?, ?),
	cell(:, ?, ?, ?, ?, ?, ?, ?).

:- dynamic
	ods_spreadsheet/2.		% URL, Module

%%	ods_DOM(+File, -DOM, +Options) is det.
%
%	DOM is the XML domtree of  the   content  file  of the given ODS
%	document.

ods_DOM(File, DOM, Options) :-
	setup_call_cleanup(
	    archive_open(File, Archive, []),
	    archive_dom(Archive, DOM, Options),
	    archive_close(Archive)).

archive_dom(Archive, DOM, Options) :-
	select_option(member(Member), Options, XMLOptions, 'content.xml'),
	archive_next_header(Archive, Member),
	setup_call_cleanup(
	    archive_open_entry(Archive, Stream),
	    load_structure(Stream, DOM, XMLOptions),
	    close(Stream)).

%%	ods_load(:Data)
%
%	Load a spreadsheet. Data is either a parsed XML DOM, a file name
%	or a URI. Tables in the spreadsheet  are converted into a set of
%	Prolog  predicates  in  the  calling    module.   The  generated
%	predicates are:
%
%	    - sheet(Name, Style)
%	    - col(Table, X, Style)
%	    - row(Table, Y, Style)
%	    - cell(Table, ID, Value, Type, Formula, Style, Annotation)
%	    - span(ID, IDBase)
%	    - style(Style, Properties)
%
%	Does nothing if the spreadsheet is  already loaded in the target
%	module. To force reloading, first use ods_unload/0.

ods_load(Module:DOM) :-
	nonvar(DOM),
	DOM = [element(_,_,_)], !,
	load_styles(DOM, Module),
	load_tables(DOM, Module).
ods_load(Module:Spec) :-
	(   uri_is_global(Spec)
	->  uri_file_name(Spec, File),
	    URI = Spec
	;   uri_file_name(URI, Spec),
	    File = Spec
	),
	(   ods_spreadsheet(URI, Module)
	->  true
	;   statistics(cputime, CPU0),
	    ods_DOM(File, DOM, []),
	    dynamic_decls(Module),
	    ods_load(Module:DOM),
	    statistics(cputime, CPU1),
	    CPU is CPU1-CPU0,
	    predicate_property(Module:sheet(_,_),
			       number_of_clauses(Sheets)),
	    predicate_property(Module:cell(_,_,_,_,_,_,_),
			       number_of_clauses(Cells)),
	    print_message(informational,
			  ods(loaded(Module:Spec, CPU, Sheets, Cells))),
	    retractall(ods_spreadsheet(URI, _)),
	    assertz(ods_spreadsheet(URI, Module))
	).

%%	ods_ensure_loaded(+URL, -Module) is semidet.
%
%	True when the spreadsheet in URL is loaded into Module.

ods_ensure_loaded(URI, Module) :-
	ods_spreadsheet(URI, Module), !,
	Module \= #(_).
ods_ensure_loaded(URI, Module) :-
	uri_file_name(URI, File),
	(   access_file(File, read)
	->  ods_load(URI:File),
	    Module = URI
	;   assertz(ods_spreadsheet(URI, #('REF!')))
	).


%%	cell_id(+X, +Y, -ID) is det.
%%	cell_id(-X, -Y, +ID) is det.

cell_id(X, Y, ID) :-
	nonvar(X), nonvar(Y), !,
	(   integer(X)
	->  ID is Y*10000+X
	;   upcase_atom(X, XU),
	    column_name(I, XU),
	    ID is Y*10000+I
	).
cell_id(X, Y, ID) :-
	nonvar(ID), !,
	Y is ID//10000,
	X is ID mod 10000.

load_tables(DOM, Module) :-
	forall(xpath(DOM, //'table:table'(@'table:name'=Name,
					  @'table:style-name'=Style), Table),
	       load_table(Table, Name, Style, Module)).

load_table(DOM, Name, TStyle, Module) :-
	assertz(Module:sheet(Name, TStyle)),
	State = state(1,1,Name,_),
	forall(xpath(DOM, 'table:table-column'(@'table:style-name'=Style), Col),
	       load_column(Col, Style, State, Module)),
	forall(xpath(DOM, 'table:table-row'(@'table:style-name'=Style), Col),
	       load_row(Col, Style, State, Module)).

load_column(element(_, CollAttrs, []), Style, State, Module) :-
	arg(1, State, X0),
	arg(3, State, Table),
	(   memberchk('table:number-columns-repeated'=RepA, CollAttrs),
	    atom_number(RepA, Rep)
	->  true
	;   Rep = 1
	),
	End is X0+Rep-1,
	forall(between(X0, End, X),
	       assertz(Module:col(Table, X, Style))),
	NextX is End+1,
	nb_setarg(1, State, NextX).

load_row(DOM, Style, State, Module) :-
	DOM = element(_, RowAttrs, _),
	nb_setarg(1, State, 1),
	arg(2, State, Y0),
	arg(3, State, Table),
	(   memberchk('table:number-rows-repeated'=RepA, RowAttrs),
	    atom_number(RepA, Rep)
	->  true
	;   Rep = 1
	),
	End is Y0+Rep-1,
	(   nonempty_row(DOM)
	->  forall(between(Y0, End, Y),
		   ( assertz(Module:row(Table, Y, Style)),
		     debug(ods(row), 'Processing row ~q', [Y]),
		     forall(xpath(DOM, 'table:table-cell'(self), Cell),
			    load_cell(Cell, State, Module))
		   ))
	;   true
	),
	NextY is End + 1,
	nb_setarg(2, State, NextY).

nonempty_row(DOM) :-
	xpath(DOM, 'table:table-cell'(content), Content),
	Content \== [].

load_cell(DOM, State, Module) :-
	DOM = element(_, CellAttrs, Content),
	arg(1, State, X0),
	arg(2, State, Y),
	arg(3, State, Table),
	(   memberchk('table:number-columns-repeated'=RepA, CellAttrs),
	    atom_number(RepA, Rep)
	->  Columns = Rep,  Repeat = Rep, Span = 1
	;   memberchk('table:number-columns-spanned'=SpanA, CellAttrs),
	    atom_number(SpanA, Span)
	->  Columns = Span, Repeat = 1
	;   Columns = 1,    Repeat = 1, Span = 1
	),
	(   memberchk('table:number-rows-spanned'=VSpanA, CellAttrs),
	    atom_number(VSpanA, VSpan)
	->  true
	;   VSpan = 1
	),
	EndRep is X0+Repeat-1,
	(   Content == []
	->  debug(ods(cell), '~w empty cells', [Columns]),
	    (	cell_style(DOM, Style),
		Style \== default
	    ->	forall(between(X0, EndRep, X),
		       ( debug(ods(cell), '~q,~q: ~q', [X,Y,Value]),
			 cell_id(X,Y,Id),
			 assertz(Module:cell(Table,Id,
					     @empty,
					     no_type,
					     -,
					     Style,
					     []))
		       ))
	    ;	true
	    )
	;   Content = [Annotation],
	    xpath(Annotation, /'office:annotation'(self), _)
	->  (   cell_style(DOM, Style),
	        cell_annotations(DOM, Annotations)
	    ->	forall(between(X0, EndRep, X),
		       ( debug(ods(cell), '~q,~q: ~q', [X,Y,Value]),
			 cell_id(X,Y,Id),
			 assertz(Module:cell(Table,Id,
					     @empty,
					     no_type,
					     -,
					     Style,
					     Annotations))
		       ))
	    ;	ods_warning(convert_failed(cell, DOM))
	    )
	;   (   cell_type(DOM, Type),
	        cell_style(DOM, Style),
		cell_value(DOM, Type, Value),
		cell_formula(DOM, Table, Formula),
		cell_annotations(DOM, Annotations)
	    ->  forall(between(X0, EndRep, X),
		       ( debug(ods(cell), '~q,~q: ~q', [X,Y,Value]),
			 cell_id(X,Y,Id),
			 assertz(Module:cell(Table,Id,
					     Value,
					     Type,
					     Formula,
					     Style,
					     Annotations))
		       ))
	    ;	ods_warning(convert_failed(cell, DOM))
	    )
	),
	(   (Span > 1 ; VSpan > 1)
	->  cell_id(X0,Y,Id0),
	    EndSpanX is X0+Columns-1,
	    EndSpanY is Y+VSpan-1,
	    forall(between(Y, EndSpanY, YS),
		   forall(between(X0, EndSpanX, XS),
			  ( cell_id(XS,YS,IDS),
			    (	IDS \== Id0
			    ->	assertz(Module:span(IDS, Id0))
			    ;	true
			    )
			  )))
	;   true
	),
	NextX is X0+Columns,
	nb_setarg(1, State, NextX).


cell_type(DOM, Type) :-
	xpath(DOM, /'table:table-cell'(@'office:value-type'), OfficeType),
	OfficeType = Type.

cell_style(DOM, Style) :-
	xpath(DOM, /'table:table-cell'(@'table:style-name'), Style), !.
cell_style(_, default).			% TBD: Use default column style

cell_value(DOM, Type, Value) :-
	xpath(DOM, /'table:table-cell'(@'office:value'), OfficeValue), !,
	convert_value(Type, OfficeValue, Value).
cell_value(DOM, date, Value) :-
	xpath(DOM, /'table:table-cell'(@'office:date-value'), OfficeValue), !,
	convert_date(OfficeValue, Value).
cell_value(DOM, string, Value) :-
	findall(T, xpath(DOM, 'text:p'(normalize_space), T), List),
	atomic_list_concat(List, Value).

convert_value(float, Text, Value) :- !,
	(   atom_number(Text, Value0)
	->  Value is float(Value0)
	;   type_error(float, Text)
	).
convert_value(percentage, Text, Value) :- !,
	(   atom_number(Text, Value0)
	->  Value is float(Value0)
	;   type_error(percentage, Text)
	).
convert_value(Type, Value, Value) :-
	ods_warning(unknown_type(Type)).

convert_date(Text, date(Y,M,D)) :-
	atom_codes(Text, Codes),
	phrase(date(Y,M,D), Codes), !.
convert_date(Text, Text) :-
	ods_warning(convert_failed(date, Text)).

date(Y,M,D) -->
	integer(Y), "-", integer(M), "-", integer(D),
	{ between(1, 12, M),
	  between(1, 31, D)
	}.

%%	cell_annotations(+DOM, -Annotations:list) is det.

cell_annotations(DOM, Annotations) :-
	findall(Annot, cell_annotation(DOM, Annot), Annotations).

cell_annotation(DOM, Term) :-
	xpath(DOM, 'office:annotation'(self), Annotation),
	(   convert_annotation(Annotation, Term)
	->  true
	;   ods_warning(convert_failed(annotation, DOM))
	).

convert_annotation(DOM, annotation(Date, Author, Text)) :-
	xpath(DOM, 'dc:date'(text), DateText),
	parse_time(DateText, Date),
	findall(T, xpath(DOM, 'text:p'(text), T), List),
	List = [Author|Rest],
	atomic_list_concat(Rest, Text).

%%	cell_formula(+DOM, +Table, -Formula) is det.

cell_formula(DOM, Table, Formula) :-
	xpath(DOM, /'table:table-cell'(@'table:formula'), OfficeFormula), !,
	(   compile_formula(OfficeFormula, Table, Formula)
	->  true
	;   ods_warning(convert_failed(formula, OfficeFormula)),
	    Formula = OfficeFormula
	).
cell_formula(_, _, -).


		 /*******************************
		 *	      STYLES		*
		 *******************************/

%%	load_styles(+DOM, +Module) is det.
%
%	Load the style information for the  spreadsheet. We simply store
%	the DOM content of the style,   leaving the high-level reasoning
%	to other predicates. One  advantage  of   this  is  that  we can
%	re-generate the style info.
%
%	@tbd	Styles defined here may refer to styles in =|styles.xml|=.

load_styles(DOM, Module) :-
	xpath(DOM, //'office:automatic-styles'(self), StylesDOM), !,
	forall(xpath(StylesDOM, 'style:style'(@'style:name' = Name), SDOM),
	       assertz(Module:style(Name, SDOM))).

%%	ods_style_property(:Style, ?Property) is nondet.
%
%	True when Property is a property   of Style. Currently extracted
%	styles are:
%
%	  * font_weight(Weight)
%	  Font weight (e.g., =bold=)
%	  * font_name(Name)
%	  Name of the font used for the text
%	  * font_size(Size)
%	  Size of the font.  See below for size representations.
%	  * column_width(Width)
%	  Width of the column
%	  * cell_color(Color)
%	  Color of the cell background
%	  * name(Name)
%	  Name of the style.
%
%	Sizes are expressed as one of pt(Points), cm(Centimeters) or
%	mm(Millimeters)
%
%	@tbd	Normalize sizes?
%	@see http://docs.oasis-open.org/office/v1.2/OpenDocument-v1.2-part1.html

ods_style_property(Module:Style, Property) :-
	Module:style(Style, DOM),
	(   nonvar(Property)
	->  once(style_property(Property, DOM))
	;   style_property(Property, DOM)
	).

style_property(font_weight(W), DOM) :-
	xpath(DOM, 'style:text-properties'(@'fo:font-weight'=W), _).
style_property(font_name(Name), DOM) :-
	xpath(DOM, 'style:text-properties'(@'style:font-name'=Name), _).
style_property(name(Name), DOM) :-
	xpath(DOM, /'style:style'(@'style:name'=Name), _).
style_property(font_size(Size), DOM) :-
	xpath(DOM, 'style:text-properties'(@'fo:font-size'=Size0), _),
	convert_size(Size0, Size).
style_property(column_width(Size), DOM) :-
	xpath(DOM, 'style:table-column-properties'(@'style:column-width'=Size0), _),
	convert_size(Size0, Size).
style_property(cell_color(Color), DOM) :-
	xpath(DOM, 'style:table-cell-properties'(@'fo:background-color'=Color),_),
	Color \== transparent.

convert_size(Atom, Term) :-
	size_suffix(Suffix),
	atom_concat(NumA, Suffix, Atom),
	atom_number(NumA, Num), !,
	Term =.. [Suffix,Num].
convert_size(Atom, Atom) :-
	ods_warning(unknown_size(Atom)).

size_suffix(pt).
size_suffix(cm).
size_suffix(mm).

		 /*******************************
		 *	      FORMULAS		*
		 *******************************/

%%	compile_formula(OfficeFormula, Table, Formula) is det.
%
%	Compile a formula into a  Prolog   expression.  Cells are of the
%	form cell(X,Y).
%
%	@see http://en.wikipedia.org/wiki/OpenFormula
%	@see http://docs.oasis-open.org/office/v1.2/OpenDocument-v1.2-part2.html

compile_formula(Text, Table, Formula) :-
	atom_codes(Text, Codes),
	phrase(formula(Formula, Table), Codes), !.

formula(Formula, Table) -->
	"of:=",
	expression(Formula, 1200, _, Table).

expression(Expr, Pri, RPri, Table) -->
	blanks,
	(   ods_number(Expr0)
	;   ods_string(Expr0)
%	;   ods_array(Expr0)
	;   ods_prefix_func(Expr0, Pri, RPri0, Table)
	;   "(", expression(Expr0, 1200, _, Table), ")"
	;   ods_function_call(Expr0, Table)
	;   ods_reference(Expr0, Table)
%	;   ods_quoted_label(Expr0)
%	;   ods_automatic_intersection(Expr0)
%	;   ods_named_expression(Expr0)
%	;   ods_error(Expr0)
	), blanks, !,
	{ var(RPri0) -> RPri0 = 0 ; true },
	ods_op_func(Expr0, Pri, RPri0, RPri, Expr, Table).

ods_prefix_func(Expr, Pri, OpPri, Table) -->
	ods_op(Op, prefix(OpPri, ArgPri)),
	{ OpPri =< Pri },
	expression(Expr0, ArgPri, _, Table),
	{ Expr =.. [Op,Expr0] }.

%%	ods_op_func(+LeftExpr, +MaxPri, +LeftExprPri, -Expr) is semidet.

ods_op_func(Left, Pri, PriL, RPri, Expr, Table) -->
	ods_op(Op, infix(OpPri, LeftPri, RightPri)),
	{ PriL =< LeftPri, OpPri =< Pri },
	expression(Right, RightPri, _, Table),
	{ Expr1 =.. [Op,Left,Right] },
	ods_op_func(Expr1, Pri, OpPri, RPri, Expr, Table).
ods_op_func(Left, Pri, PriL, RPri, Expr, Table) -->
	ods_op(Op, postfix(OpPri, LeftPri)),
	{ PriL =< LeftPri, OpPri =< Pri },
	{ Expr1 =.. [Op,Left] },
	ods_op_func(Expr1, Pri, OpPri, RPri, Expr, Table).
ods_op_func(Expr, _, Pri, Pri, Expr, _) -->
	"".

ods_op(Op, Type) -->
	ods_op(Op),
	{ ods_op(Op, Type) }.

ods_op(':') --> ":".
ods_op('!') --> "!".
ods_op('~') --> "~".
ods_op('+') --> "+".
ods_op('-') --> "-".
ods_op('%') --> "%".
ods_op('^') --> "^".
ods_op('*') --> "*".
ods_op('/') --> "/".
ods_op('&') --> "&".
ods_op('=') --> "=".
ods_op('<>') --> "<>".
ods_op('<=') --> "<=".
ods_op('<') --> "<".
ods_op('>=') --> ">=".
ods_op('>') --> ">".

ods_op(':', infix(10, 10, 9)).
ods_op('!', infix(20, 20, 19)).
ods_op('~', infix(30, 30, 29)).
ods_op('+', prefix(40, 40)).
ods_op('-', prefix(40, 40)).
ods_op('%', postfix(50, 50)).
ods_op('^', infix(60, 60, 59)).
ods_op('*', infix(70, 70, 69)).
ods_op('/', infix(70, 70, 69)).
ods_op('+', infix(80, 80, 79)).
ods_op('-', infix(80, 80, 79)).
ods_op('&', infix(90, 90, 89)).
ods_op('=', infix(100, 100, 99)).
ods_op('<>', infix(100, 100, 99)).
ods_op('<', infix(100, 100, 99)).
ods_op('<=', infix(100, 100, 99)).
ods_op('>', infix(100, 100, 99)).
ods_op('>=', infix(100, 100, 99)).

%%	ods_number(-Number)// is semidet.
%
%	Deal with numbers that start with . instead of 0.

ods_number(N) -->
	number(N), !.
ods_number(N) -->
	dot,
	digit(DF0),
	digits(DF),
	{ F = [0'0, 0'., DF0|DF] },
	(   exp
	->  int_codes(DI),
	    {E=[0'e|DI]}
	;   {E = ""}
	),
	{ append([F, E], Codes),
	  number_codes(N, Codes)
	}.

int_codes([C,D0|D]) -->
	sign(C), !,
	digit(D0),
	digits(D).
int_codes([D0|D]) -->
	digit(D0),
	digits(D).

sign(0'-) --> "-".
sign(0'+) --> "+".

dot --> ".".

exp --> "e".
exp --> "E".

%%	ods_string(-Atom)//

ods_string(String) -->
	"\"", str_codes(Codes), "\"",
	{ atom_codes(String, Codes) }.

str_codes([H|T]) -->
	str_code(H), !,
	str_codes(T).
str_codes([]) -->
	"".

str_code(0'") --> "\"\"", !.
str_code(C) --> [C], { C \== 0'" }.

%%	ods_function_call(Expr0)// is semidet.

ods_function_call(eval(Expr), Table) -->
	function_name(Name),
	blanks, "(", parameter_list(Args, Table),
	{ Expr =.. [Name|Args] }.

parameter_list([], _) -->
	")", !.
parameter_list([H|T], Table) -->
	expression(H, 1200, _, Table), !, blanks,
	(   ";"
	->  blanks,
	    parameter_list(T, Table)
	;   ")"
	->  { T = [] }
	).

function_name(Name) -->
	letter_xml(C0),
	function_name_codes(C),
	{ atom_codes(Name, [C0|C]) }.

function_name_codes([H|T]) -->
	function_name_code(H), !,
	function_name_codes(T).
function_name_codes([]) --> "".

function_name_code(C) -->
	[C],
	{ xml_basechar(C)
	; xml_digit(C)
	; C == 0'_
	; C == 0'.
	; xml_ideographic(C)
	; xml_combining_char(C)
	}, !.


letter_xml(C) --> [C], { xml_basechar(C) ;
			 xml_ideographic(C)
		       }, !.

%%	ods_reference(Expr0, Table)

ods_reference(Expr, Table) -->
	"[", reference(Expr, Table), "]", !.

reference(ext(IRI, Range), Table) -->
	"'", !, string(Codes), "'#",
	{ atom_codes(IRI0, Codes),
	  fixup_reference(IRI0, IRI)
	},
	range_address(Range, Table).
reference(Range, Table) -->
	range_address(Range, Table).
reference(#('REF!'), _) -->
	"#REF!".

:- dynamic
	fixed_up/2.

fixup_reference(IRI0, IRI) :-
	fixed_up(IRI0, IRI), !.
fixup_reference(IRI0, IRI) :-
	uri_file_name(IRI0, File),
	(   access_file(File, read)
	->  IRI = IRI0
	;   file_base_name(File, Base),
	    file_name_extension(Plain, _, Base),
	    file_name_extension(Plain, ods, Local),
	    access_file(Local, read)
	->  uri_file_name(IRI, Local),
	    print_message(informational, ods(updated_ext(IRI0, IRI)))
	;   print_message(warning, ods(no_ext(IRI0))),
	    IRI = IRI0
	),
	assertz(fixed_up(IRI0, IRI)).

clean_fixup :-
	retractall(fixed_up(_,_)).

%%	range_address(-Ref, +DefaultTable)

range_address(Ref, Table) -->
	sheet_locator_or_empty(Sheet, Table),
	".",
	(   cell(SX,SY)
	->  (   ":."
	    ->  cell(EX,EY),
		{ Ref = cell_range(Sheet, SX, SY, EX, EY) }
	    ;   { Ref = cell(Sheet, SX, SY) }
	    )
	;   column(Start)
	->  ":.",
	    column(End),
	    { Ref = col_range(Sheet, Start, End) }
	;   row(Start)
	->  ":.",
	    row(End),
	    { Ref = row_range(Sheet, Start, End) }
	).
range_address(Ref, _Table) -->
	sheet_locator(Sheet),
	".",
	(   cell(SX, SY)
	->  ":",
	    sheet_locator(Sheet2), cell(EX, EY),
	    { Ref = xcell_range(Sheet, SX, SY, Sheet2, EX, EY) }
	;   column(Start)
	->  ":",
	    sheet_locator(Sheet2), column(End),
	    { Ref = xcol_range(Sheet, Start, Sheet2, End) }
	;   row(Start)
	->  ":",
	    sheet_locator(Sheet2), row(End),
	    { Ref = xrow_range(Sheet, Start, Sheet2, End) }
	).

sheet_locator_or_empty(Sheet, _) -->
	sheet_locator(Sheet).
sheet_locator_or_empty(Table, Table) --> "".

sheet_locator(Sheet) -->
	sheet_name(Name),
	subtable_path(Name, Sheet).

subtable_path(Name, Locator) -->
	".",
	subtable_cell(One),
	{ Path0 = Name/One },
	subtable_path(Path0, Locator).
subtable_path(Path, Path) --> "".

subtable_cell(Cell) -->
	cell(Cell), !.
subtable_cell(Sheet) -->
	sheet_name(Sheet).

sheet_name(Name) -->
	( "$" ->  "" ; "" ),
	(   single_quoted(Name)
	;   sheet_name_code(C0),
	    sheet_name_codes(Codes)
	->  { atom_codes(Name, [C0|Codes]) }
	).

cell(cell(X,Y)) -->
	column(X),
	row(Y).

cell(X, Y) -->
	column(X),
	row(Y).

column(Col) -->
	( "$" ->  "" ; "" ),
	coln(0, Col).

coln(C0, C) -->
	[D],
	{ between(0'A, 0'Z, D), !,
	  C1 is C0*26+D-0'A+1
	},
	coln(C1, C).
coln(C, C) --> "".

row(Row) -->
	( "$" ->  "" ; "" ),
	rown(0, Row).

rown(R0, R) -->
	[D],
	{ between(0'0, 0'9, D), !,
	  R1 is R0*10+D-0'0
	},
	rown(R1, R).
rown(R, R) --> "".


%%	single_quoted(-Atom)

single_quoted(String) -->
	"'", sq_codes(Codes), "'",
	{ atom_codes(String, Codes) }.

sq_codes([H|T]) -->
	sq_code(H), !,
	sq_codes(T).
sq_codes([]) -->
	"".

sq_code(0'\') --> "''", !.
sq_code(C) --> [C], { C \== 0'\' }.

sheet_name_codes([H|T]) -->
	sheet_name_code(H), !,
	sheet_name_codes(T).
sheet_name_codes([]) --> "".

sheet_name_code(C) -->
	[C],
	{ \+ not_in_sheet_name(C) }.

not_in_sheet_name(0']).
not_in_sheet_name(0'.).
not_in_sheet_name(0'\s).
not_in_sheet_name(0'#).
not_in_sheet_name(0'$).

%%	sheet_name_need_quotes(+Name) is semidet.
%
%	True when Name is a sheet name that needs (single) quotes.

sheet_name_need_quotes(Name) :-
	atom_codes(Name, Codes),
	member(Code, Codes),
	not_in_sheet_name(Code), !.


		 /*******************************
		 *	 CELL PROPERTIES	*
		 *******************************/

%%	cell_value(:Sheet, ?X, ?Y, ?Value)
%
%	True when cell X,Y in Sheet has Value.

cell_value(Module:Sheet, X, Y, Value) :-
	(   ground(cell(Sheet,X,Y))
	->  cell_id(X,Y,Id),
	    once(Module:cell(Sheet, Id, Value, _, _, _, _))
	;   Module:cell(Sheet, Id, Value, _, _, _, _),
	    cell_id(X,Y,Id)
	),
	Value \== @empty.

%%	cell_type(:Sheet, ?X, ?Y, ?Type)
%
%	True when cell X,Y in Sheet has Type.

cell_type(Module:Sheet, X, Y, Type) :-
	(   ground(cell(Sheet,X,Y))
	->  cell_id(X,Y,Id),
	    once(Module:cell(Sheet, Id, _, Type, _, _, _))
	;   Module:cell(Sheet, Id, _, Type, _, _, _),
	    cell_id(X,Y,Id)
	).

%%	cell_formula(:Sheet, ?X, ?Y, ?Formula)
%
%	True when cell X,Y in Sheet has Formula.

cell_formula(Module:Sheet, X, Y, Formula) :-
	(   ground(cell(Sheet,X,Y))
	->  cell_id(X,Y,Id),
	    once(Module:cell(Sheet, Id, _, _, Formula, _, _))
	;   Module:cell(Sheet, Id, _, _, Formula, _, _),
	    cell_id(X,Y,Id)
	),
	Formula \== (-).

%%	cell_eval(:Sheet, ?X, ?Y, ?Value)
%
%	True when the formula of cell X,Y in Sheet evaluates to Value

cell_eval(Sheet, X, Y, Value) :-
	cell_formula(Sheet, X, Y, Formula),
	cell_type(Sheet, X, Y, Type),
	Sheet = Module:_,
	ods_eval_typed(Formula, Type, Value, Module).

%%	cell_style(:Sheet, ?X, ?Y, ?Style)
%
%	True when cell X,Y  in  Sheet   has  style  property  Style. See
%	ods_style_property/2 for supported styles.

cell_style(Sheet, X, Y, Property) :-
	nonvar(Property), !,
	style_property_level(Property, Where),
	cell_style(Where, Sheet, X, Y, Property).
cell_style(Sheet, X, Y, Property) :-
	cell_style(_, Sheet, X, Y, Property).

cell_style(cell, Module:Sheet, X, Y, Property) :-
	(   ground(cell(Sheet,X,Y))
	->  cell_id(X,Y,Id),
	    once(Module:cell(Sheet, Id, _, _, _, Style, _))
	;   Module:cell(Sheet, Id, _, _, _, Style, _),
	    cell_id(X,Y,Id)
	),
	ods_style_property(Module:Style, Property).
cell_style(column, Module:Sheet, Col, _, Property) :-
	(   ground(cell(Sheet,Col))
	->  column_id(Col, X),
	    once(Module:col(Sheet, X, Style))
	;   Module:col(Sheet, Col, Style)
	),
	ods_style_property(Module:Style, Property).

column_id(Col, X) :-
	(   integer(Col)
	->  X = Col
	;   upcase_atom(Col, Up),
	    column_name(X, Up)
	).

style_property_level(column_width(_),	column).
style_property_level(font_weight(_),	cell).
style_property_level(font_name(_),	cell).
style_property_level(font_size(_),	cell).
style_property_level(cell_color(_),	cell).
style_property_level(name(_),		cell).

%%	cell(:Sheet, ?X, ?Y, ?Value, ?Type, ?Formula, ?Style, ?Annotations)
%
%	Query raw cells.

cell(M:Sheet, X, Y, Value, Type, Formula, Style, Annot) :-
	(   ground(cell(Sheet,X,Y))
	->  cell_id(X,Y,Id),
	    once(M:cell(Sheet, Id, Value, Type, Formula, Style, Annot))
        ;   M:cell(Sheet, Id, Value, Type, Formula, Style, Annot),
	    cell_id(X,Y,Id)
	).


		 /*******************************
		 *    EXPRESSION EVALUATION	*
		 *******************************/

%%	ods_eval(:Expression, -Value) is det.
%
%	Evaluate an expression.

ods_eval(Module:Expression, Value) :-
	ods_eval(Expression, Value, Module).

ods_eval(cell(Sheet,X,Y), Value, Module) :- !,
	cell_value(Sheet,X,Y, _Type, Value, Module).
ods_eval(cell_range(Sheet, SX,SY, EX,EY), List, M) :- !,
	(   SX =:= EX
	->  col_array(Sheet, SX, SY, EY, List, M)
	;   SY =:= EY
	->  row_array(Sheet, SY, SX, EX, List, M)
	;   array(Sheet, SX,SY, EX,EY, List, M)
	).
ods_eval(Ref1:Ref2, Value, Module) :- !,
	eval_reference(Ref1, cell(S,SX,SY), Module),
	eval_reference(Ref2, cell(S,EX,EY), Module),
	ods_eval(cell_range(S,SX,SY,EX,EY), Value, Module).
ods_eval(ext(URL, Ref), Value, _Module) :- !,
	(   ods_ensure_loaded(URL, MExt)
	->  ods_eval(Ref, Value, MExt)
	;   ods_warning(no_ext(URL)),
	    Value = #('REF!')
	).
ods_eval(eval(Expr), Value, M) :- !,
	eval_function(Expr, Value, M).
ods_eval(A+B, Value, M) :- !,
	ods_eval_typed(A, number, VA, M),
	ods_eval_typed(B, number, VB, M),
	Value is VA+VB.
ods_eval(A-B, Value, M) :- !,
	ods_eval_typed(A, number, VA, M),
	ods_eval_typed(B, number, VB, M),
	Value is VA-VB.
ods_eval(A*B, Value, M) :- !,
	ods_eval_typed(A, number, VA, M),
	ods_eval_typed(B, number, VB, M),
	Value is VA*VB.
ods_eval(A/B, Value, M) :- !,
	ods_eval_typed(A, number, VA, M),
	ods_eval_typed(B, number, VB, M),
	(   VB =:= 0
	->  Value = #('DIV/0!')
	;   Value is VA/VB
	).
ods_eval(-A, Value, M) :- !,
	ods_eval_typed(A, number, VA, M),
	Value is -VA.
ods_eval(+A, Value, M) :- !,
	ods_eval_typed(A, number, Value, M).
ods_eval(A=B, Value, M) :- !,
	ods_eval(A, VA, M),
	ods_eval(B, VB, M),
	(   ods_equal(VA, VB)
	->  Value = @true
	;   Value = @false
	).
ods_eval(A>B, Value, M) :- !,		% compare numbers, text, boolean
	ods_eval(A, VA, M),		% different types: undefined.
	ods_eval(B, VB, M),
	(   VA @> VB
	->  Value = @true
	;   Value = @false
	).
ods_eval(A>=B, Value, M) :- !,
	ods_eval(A, VA, M),
	ods_eval(B, VB, M),
	(   VA @>= VB
	->  Value = @true
	;   Value = @false
	).
ods_eval(A<B, Value, M) :- !,
	ods_eval(A, VA, M),
	ods_eval(B, VB, M),
	(   VA @< VB
	->  Value = @true
	;   Value = @false
	).
ods_eval('<='(A,B), Value, M) :- !,
	ods_eval(A, VA, M),
	ods_eval(B, VB, M),
	(   VA @=< VB
	->  Value = @true
	;   Value = @false
	).
ods_eval('%'(A), Value, M) :- !,
	ods_eval(A, VA, M),
	(   VA >= 0, VA =< 100
	->  Value is VA/100.0
	;   domain_error(percentage, VA)
	).
ods_eval(#(Error), #(Error), _) :- !.
ods_eval(X, X, _).

ods_eval_typed(cell(Sheet, X, Y), Type, Value, M) :- !,
	cell_value(Sheet,X,Y, Type, Value, M).
ods_eval_typed(Expr, Type, Value, M) :-
	ods_eval(Expr, Value0, M),
	type_convert(Type, Value0, Value).

cell_value(Sheet,X,Y, Type, Value, M) :-
	(   cell_id(X,Y,Id),
	    M:cell(Sheet, Id, Value0, _Type, _, _, _)
	->  type_convert(Type, Value0, Value)
	;   no_cell(Sheet,X,Y),
	    type_default(Type, Value0)
	->  Value = Value0
	).

%%	eval_reference(+Spec, -Ref, +Module)
%
%	Evaluate an expression to a reference.

eval_reference(Ref, Ref, _) :-
	is_reference(Ref), !.
eval_reference(eval('OFFSET'(Ref0, OXExpr, OYExpr)), Ref, M) :-
	ods_eval_typed(OXExpr, integer, OX, M),
	ods_eval_typed(OYExpr, integer, OY, M),
	offset_reference(Ref0, OX, OY, Ref).

is_reference(#(_)).
is_reference(cell(_,_,_)).
is_reference(cell_range(_,_,_,_,_)).

%%	offset_reference(+Ref0, +OX, +OY, -Ref)

offset_reference(cell(S,X0,Y0), OffX, OffY, cell(S,X,Y)) :- !,
	X is X0 + OffX,
	Y is Y0 + OffY.
offset_reference(cell_range(S,SX0,SY0,EX0,EY0), OffX, OffY,
		 cell_range(S,SX,SY,EX,EY)) :- !,
	SX is SX0 + OffX,
	SY is SY0 + OffY,
	EX is EX0 + OffX,
	EY is EY0 + OffY.
offset_reference(_, _, _, #('REF!')).

%%	col_array(+Sheet, +X, +SY, +EY, -Array, +Module) is det.
%
%	Produce an array of values for a column, represented as a list.

col_array(Sheet, X, Y0, Y, [V0|VL], M) :-
	Y0 =< Y, !,
	cell_id(X,Y0,Id),
	(   M:cell(Sheet, Id, V0, _Type, _, _, _)
	->  true
	;   V0 = @empty
	),
	Y1 is Y0+1,
	col_array(Sheet, X, Y1, Y, VL, M).
col_array(_, _, _, _, [], _).


%%	row_array(+Sheet, +Y, +SX, +EX, -Array, +Module) is det.
%
%	Produce an array of values for a row, represented as a list.

row_array(Sheet, Y, X0, X, [V0|VL], M) :-
	X0 =< X, !,
	cell_id(X0,Y,Id),
	(   M:cell(Sheet, Id, V0, _Type, _, _, _)
	->  true
	;   V0 = @empty
	),
	X1 is X0+1,
	row_array(Sheet, Y, X1, X, VL, M).
row_array(_, _, _, _, [], _).

%%	array(+Sheet, +SX, +SY, +EX, +EY, -Array, +Module) is det.
%
%	Array is a two-dimenional list of values in the range SXSY:EXEY.

array(Sheet, SX, Y0, EX, Y, [R1|RL], Module) :-
	Y0 =< Y, !,
	row_array(Sheet, Y0, SX, EX, R1, Module),
	Y1 is Y0+1,
	array(Sheet, SX, Y1, EX, Y, RL, Module).
array(_, _, _, _, _, [], _).



%%	eval_function(+FunctionTerm, -Value, +Module)

eval_function('IF'(Cond, Then, Else), Value, M) :- !,
	ods_eval(Cond, VC, M),
	(   VC == @true
	->  ods_eval(Then, Value, M)
	;   ods_eval(Else, Value, M)
	).
eval_function('VLOOKUP'(VExpr, DataSource, ColExpr), Value, M) :- !,
	ods_eval(VExpr, V, M),
	(   DataSource = cell_range(Sheet, SX,SY, EX,EY),
	    ods_eval_typed(ColExpr, integer, Column, M),
	    Column \= #(_),
	    TX is SX+Column-1,
	    TX =< EX
	->  (   bisect(range_vtest(V, Sheet, SX), SY, EY, TY)
	    ->	cell_value(Sheet, TX, TY, Value)
	    ;	Value = #('N/A')
	    )
	;   print_message(error, ods(invalid_vlookup)),
	    Value = #('N/A')
	).
eval_function('VLOOKUP'(VExpr, DataSource, ColExpr, Sorted), Value, M) :- !,
	(   ods_eval(Sorted, @false, M)
	->  ods_eval(VExpr, V, M),
	    (	DataSource = cell_range(Sheet, SX,SY, EX,EY)
	    ->	(   ods_eval_typed(ColExpr, integer, Column, M),
		    TX is SX+Column-1,
		    TX =< EX,		% TBD: range error
		    between(SY, EY, Y),
		    cell_value(Sheet, SX, Y, V)
		->  cell_value(Sheet, TX, Y, Value)
		;   Value = #('N/A')
		)
	    ;	print_message(error, ods(unsupported_datasource, DataSource)),
		Value = #('N/A')
	    )
	;   eval_function('VLOOKUP'(VExpr, DataSource, ColExpr), Value, M)
	).
eval_function('HLOOKUP'(VExpr, DataSource, RowExpr), Value, M) :- !,
	ods_eval(VExpr, V, M),
	(   DataSource = cell_range(Sheet, SX,SY, EX,EY),
	    ods_eval_typed(RowExpr, integer, Row, M),
	    Row \= #(_),
	    TY is SY+Row-1,
	    TY =< EY
	->  (   bisect(range_vtest(V, Sheet, SY), SX, EX, TX)
	    ->	cell_value(Sheet, TX, TY, Value)
	    ;	Value = #('N/A')
	    )
	;   print_message(error, ods(invalid_vlookup)),
	    Value = #('N/A')
	).
eval_function('HLOOKUP'(VExpr, DataSource, ColExpr, Sorted), Value, M) :- !,
	(   ods_eval(Sorted, @false, M)
	->  ods_eval(VExpr, V, M),
	    (	DataSource = cell_range(Sheet, SX,SY, EX,EY)
	    ->	(   ods_eval_typed(ColExpr, integer, Column, M),
		    TY is SY+Column-1,
		    TY =< EY,		% TBD: range error
		    between(SX, EX, X),
		    cell_value(Sheet, X, SY, V)
		->  cell_value(Sheet, X, TY, Value)
		;   Value = #('N/A')
		)
	    ;	print_message(error, ods(unsupported_datasource, DataSource)),
		Value = #('N/A')
	    )
	;   eval_function('HLOOKUP'(VExpr, DataSource, ColExpr), Value, M)
	).
eval_function('MATCH'(VExpr, Values), Value, M) :- !,
	eval_function('MATCH'(VExpr, Values, 1), Value, M).
eval_function('MATCH'(VExpr, ValuesExpr, How), Value, M) :- !,
	ods_eval(VExpr, Target, M),
	ods_eval(ValuesExpr, Values),
	(   \+ is_list(Values)
	->  Value = #('N/A')
	;   How =:= 1
	->  (   Values = [H|_],
	        ods_before(Target, H)
	    ->	Value = #('N/A')
	    ;	nth1(Index, Values, V),
		ods_before(V, Target)
	    ->	Value is Index-1
	    ;	length(Values, Value)
	    )
	;   How =:= 0
	->  (   nth1(Index, Values, Target)
	    ->	Value = Index
	    ;	Value = #('N/A')
	    )
	;   How =:= -1
	->  (   Values = [H|_],
	        ods_before(H, Target)
	    ->	Value = #('N/A')
	    ;	nth1(Index, Values, V),
		ods_before(Target, V)
	    ->	Value is Index-1
	    ;	length(Values, Value)
	    )
	;   Value = #('N/A')
	).
eval_function('ISBLANK'(Expr), Value, M) :- !,
	(   Expr = cell(Sheet,X,Y)
	->  cell_id(X,Y,Id),
	    (	M:cell(Sheet, Id, CellValue, _Type, _, _, _),
		CellValue \== @empty
	    ->	Value = @false
	    ;	Value = @true
	    )
	;   Expr = #('REF!')		% Error reference
	->  Value = @true
	;   Value = @false
	).
eval_function('COUNTIF'(In, &(Op,To)), Value, M) :- !,
	range_goal(In, V, Goal, M),	% TBD: What about &?
	ods_eval(To, VTo),		% TBD: Comparison to empty cells
	Func =.. [Op,V,VTo],
	same_type_condition(VTo, V, TypeCond),
	aggregate_all(count,
		      ( Goal, TypeCond,
			ods_eval(Func, @true, M)
		      ),
		      Value).
eval_function(Expr, Value, M) :-
	Expr =.. [Func|ArgExprs],
	maplist(ods_evalm(M), ArgExprs, Args),
	(   eval_varargs(Func, Args, Value)
	->  true
	;   Expr1 =.. [Func|Args],
	    (   eval(Expr1, Value)
	    ->  true
	    ;   ods_error(eval(Expr1)),
		Value = #('N/A')
	    )
	).

ods_evalm(M, Expr, Value) :-
	ods_eval(Expr, Value, M).

%%	eval(+Expr, -Value) is det.

eval('SUM'(List), Value) :-
	ods_sum_list(List, Value).
eval('AVERAGE'(List), Value) :-
	length(List, Len),		% should length include @empty?
	(   Len > 0
	->  ods_sum_list(List, Sum),
	    Value is Sum/Len
	;   Value = #('N/A')
	).
eval('RANK'(V, List), Rank) :-
	msort(List, Sorted),
	reverse(Sorted, Descending),
	(   nth1(Rank, Descending, V)
	->  true
	;   Rank = #('N/A')
	).
eval('RANK'(V, List, Order), Rank) :-
	(   Order =:= 0
	->  eval('RANK'(V, List), Rank)
	;   msort(List, Ascending),
	    nth1(Rank, Ascending, V)
	->  true
	;   Rank = #('N/A')
	).
eval('ISERROR'(T), True) :-
	(   T = #(_)
	->  True = @true
	;   True = @false
	).
eval('PMT'(Rate, Nper, Pv, Fv, PayType), Value) :-
	pmt(Rate, Nper, Pv, Fv, PayType, Value).
eval('PMT'(Rate, Nper, Pv, Fv), Value) :-
	pmt(Rate, Nper, Pv, Fv, 0, Value).
eval('PMT'(Rate, Nper, Pv), Value) :-
	pmt(Rate, Nper, Pv, 0, 0, Value).
eval('ROUND'(Float), Value) :-
	Value is round(Float).
eval('ROUND'(Float, Digits), Value) :-
	(   Digits =:= 0
	->  Value is round(Float)
	;   Digits > 0
	->  Mult is 10^integer(Digits),
	    Value is round(Float*Mult)/Mult
	;   Div is 10^(-integer(Digits)),
	    Value is round(Float/Div)*Div
	).
eval('ROUNDDOWN'(Float), Value) :-
	Value is truncate(Float).
eval('ROUNDDOWN'(Float, Digits), Value) :-
	(   Digits =:= 0
	->  Value is truncate(Float)
	;   Digits > 0
	->  Mult is 10^integer(Digits),
	    Value is truncate(Float*Mult)/Mult
	;   Div is 10^(-integer(Digits)),
	    Value is truncate(Float/Div)*Div
	).
eval('EXP'(Float), Value) :-
	Value is exp(Float).
eval('FALSE', @false).
eval('TRUE', @true).

%%	eval_varargs(+Func, +Args, -Value) is semidet.

eval_varargs('MAX', Args, Value) :-
	(   Args = [List],		% MAX(DataSource)
	    is_list(List)
	->  true
	;   List = Args			% MAX(A;B;...)
	),
	(   List \== []
	->  include(number, List, Numbers),
	    max_list(Numbers, Value)
	;   Value = 0
	).
eval_varargs('MIN', Args, Value) :-
	(   Args = [List],
	    is_list(List)
	->  true
	;   List = Args
	),
	(   List \== []
	->  include(number, List, Numbers),
	    min_list(Numbers, Value)
	;   Value = 0
	).
eval_varargs('CONCATENATE', List, Value) :-
	maplist(normalize_value, List, Normalized),
	atomic_list_concat(Normalized, Value0),
	normalize_space(atom(Value), Value0). % Seems to be used.

%%	normalize_value(+Raw, -Normalized)
%
%	Normalizes floats that happen to be int to integers.

normalize_value(Float, Int) :-
	float(Float),
	float_fractional_part(Float) =:= 0.0, !,
	Int is integer(Float).
normalize_value(Value, Value).


%%	type_default(+Type, -Default).

type_default(string, '').
type_default(number, 0).
type_default(float, 0.0).
type_default(integer, 0).

%%	type_convert(+Type, +V0, -V).

type_convert(Type, V0, V) :-
	var(Type), !,
	V = V0.
type_convert(_, #(Error), #(Error)) :- !.
type_convert(number, V0, V) :-
	(   number(V0)
	->  V = V0
	;   ods_warning(convert(number, V0)),
	    (	V0 == ''
	    ->	V = 0.0
	    ;	atom_number(V0, V)
	    )
	).
type_convert(float, V0, V) :-
	(   number(V0)
	->  V is float(V0)
	;   ods_warning(convert(number, V0)),
	    (	V0 == ''
	    ->	V = 0.0
	    ;	atom_number(V0, V1),
		V is float(V1)
	    )
	).
type_convert(percentage, V0, V) :-
	type_convert(float, V0, V).
type_convert(integer, V0, V) :-
	(   number(V0)
	->  V is integer(V0)
	;   ods_warning(convert(number, V0)),
	    (	V0 == ''
	    ->	V = 0
	    ;	atom_number(V0, V1),
		V is integer(V1)
	    )
	).
type_convert(string, V0, V) :-
	(   atom(V0)
	->  V = V0
	;   ods_warning(convert(string, V0)),
	    atom_number(V, V0)
	).


no_cell(Sheet, X, Y) :-
	ods_warning(no_cell(Sheet,X,Y)).

%%	range_goal(+Spec, -Goal, +Module) is det.

range_goal(cell_range(Sheet, SX,SY, EX,EY), V, Goal, M) :- !,
	(   SX == EX
	->  Goal = ( between(SY,EY,Y),
	             ods_eval_if_exists(cell(Sheet,SX,Y), V, M)
		   )
	;   SY == EY
	->  Goal = ( between(SX,EX,X),
		     ods_eval_if_exists(cell(Sheet,X,SY), V, M)
		   )
	;   ods_warning(eval(cell_range(Sheet, SX,SY, EX,EY))),
	    Goal = fail
	).
range_goal(Expr, _, fail, _) :-
	ods_warning(range_expected(Expr)).

%%	range_vtest(+Value, +Sheet, +X, +Y) is semidet.
%
%	True if cell_value(Sheet,X,Y,V) and V is before Value.

range_vtest(Value, Sheet, X, Y) :-
	cell_value(Sheet, X, Y, V2),
	ods_before(V2, Value).

%%	ods_before(+Value1, +Value2) is semidet.
%
%	True if Value1 is before Value2 in the spreadsheet order of
%	terms.  Meaning numbers < text < logical, @false < @true.

ods_before(@X, @Y) :- !,
	ods_before_special(X,Y).
ods_before(N1, N2) :-
	number(N1), number(N2),
	N1 < N2.
ods_before(V1, V2) :-
	V1 @< V2.			% @<: number < atom < compound

ods_before_special(false, true).

%%	ods_equal(+Value1, +Value2) is semidet.
%
%	True if Value1 and Value2 have the same value.

ods_equal(X, X) :- !.
ods_equal(N1, N2) :-
	number(N1), number(N2), !,
	N1 =:= N2.

%%	same_type_condition(+Value, +Var, -Goal) is det.
%
%	True when Goal is a goal that  succeeds   if  Var is of the same
%	type as Value.

same_type_condition(Ref, V, number(V)) :-
	number(Ref), !.
same_type_condition(Ref, V, atom(V)) :-
	atom(Ref), !.
same_type_condition(Ref, _, true) :-
	ods_warning(same_type_condition(Ref)).


%%	ods_sum_list(+List, -Sum) is det.

ods_sum_list(List, Sum) :-
	ods_sum_list(List, 0, Sum).

ods_sum_list([], Sum, Sum).
ods_sum_list([H|T], Sum0, Sum) :-
	ods_add(H, Sum0, Sum1),
	ods_sum_list(T, Sum1, Sum).

ods_add(N1, N2, N) :-
	number(N1),
	number(N2), !,
	N is N1 + N2.
ods_add(@empty, Sum, Sum) :- !.
ods_add(_, #(E), #(E)) :- !.
ods_add(#(E), _, #(E)) :- !.


		 /*******************************
		 *	       UTIL		*
		 *******************************/


%%	column_name(?Index, ?Name) is det.
%
%	Name is the alplanumerical name of column  Col. Column 1 is 'A',
%	26 = 'Z', 27 = 'AA'.

column_name(N, Col) :-
	integer(N), !,
	col_chars(N, Chars, []),
	atom_codes(Col, Chars).
column_name(N, Col) :-
	atom_codes(Col, Codes),
	phrase(column(N), Codes).


col_chars(Col, [C|T], T) :-
	Col =< 26, !,
	C is Col+0'A-1.
col_chars(Col, List, T) :-
	High is Col//26,
	Last is (Col mod 26) + 0'A - 1,
	col_chars(High, List, [Last|T]).



		 /*******************************
		 *	      CLEANUP		*
		 *******************************/

%%	ods_unload
%
%	Remove saved facts from the database

:- module_transparent
	ods_unload/0,
	ods_compile/0.

ods_unload :-
	context_module(M),
	clean_fixup,
	retractall(ods_sheet:ods_spreadsheet(_, M)),
	(   predicate_property(M:sheet(_,_), dynamic)
	->  forall(data_predicate(Name/Arity),
		   ( functor(Head, Name, Arity),
		     retractall(M:Head)))
	;   forall(data_predicate(P),
		   abolish(M:P))
	).

dynamic_decls(M) :-
	forall(data_predicate(P),
	       dynamic(M:P)).

data_predicate(sheet/2).
data_predicate(col/3).
data_predicate(row/3).
data_predicate(cell/7).
data_predicate(span/2).
data_predicate(style/2).


%%	ods_unload_all is det.
%
%	Unload all currently loaded spreadsheets.

ods_unload_all :-
	forall(ods_spreadsheet(_, M),
	       M:ods_unload).


%%	ods_compile
%
%	Lock the spreadsheet predicates as static to make them faster.

ods_compile :-
	context_module(M),
	compile_predicates(M:[ sheet/2,
			       col/3,
			       row/3,
			       cell/7,
			       style/2
			     ]).

%%	ods_compile_all is det.
%
%	Compile all loaded spreadsheets

ods_compile_all :-
	forall(ods_spreadsheet(_, M),
	       M:ods_compile).


%%	ods_current(:URL) is nondet.
%
%	True when URL is the currently loaded spreadsheet.

ods_current(Module:URL) :-
	ods_spreadsheet(URL, Module).


		 /*******************************
		 *	       MESSAGES		*
		 *******************************/

%%	ods_warning(+Term)
%
%	Print message if ods(warnings) topic is enabled

ods_warning(Term) :-
	(   debugging(ods(warnings))
	->  print_message(warning, ods(Term))
	;   true
	).

ods_error(Term) :-
	print_message(error, ods(Term)).


:- multifile
	prolog:message//1.

prolog:message(ods(Msg)) -->
	message(Msg).

message(updated_ext(IRI0, IRI)) -->
	[ 'Updated external reference:'-[], nl,
	  '   ~w --> ~w'-[IRI0, IRI]
	].
message(no_ext(IRI)) -->
	[ 'Missing external reference: ~q'-[IRI] ].
message(loaded(Module:File, CPU, Sheets, Cells)) -->
	[ 'Loaded ~q into ~q; ~3f sec; ~D cells in ~D sheets'-
	  [File, Module, CPU, Cells, Sheets]
	].
