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

:- module(webui,
	  [ server/1,			% ?Port
	    show/1,			% +Data
	    show/2,			% +Data, +Options
	    clear/0
	  ]).
:- use_module(library(http/thread_httpd)).
:- use_module(library(webconsole)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/html_head)).
:- use_module(library(http/html_write)).
:- use_module(data).
:- use_module(table).
:- use_module(recognise).

:- meta_predicate
	show(:),
	show(:, +).

/** <module> Show analysis results

This module shows analysis results in  a   web  browser. The typical use
case is to show a datasource (rectangular area) as an HTML table.
*/


:- http_handler(root(.), home, []).
:- http_handler(root('webui.css'), http_reply_file('webui.css', []), []).

server(Port) :-
	http_server(http_dispatch, [port(Port)]).


home(_Request) :-
	reply_html_page(title('Spreadsheet analyzer'),
			[ \html_requires(root('webui.css')),
			  h1('Spreadsheet analyzer'),
			  \wc_error_area,
			  \wc_output_area([id(log)]),
			  \wc_form_area([id(form)])
			]).

show(Data) :-
	show(Data, []).

show(M:Data, [Options]) :-
	wc_html(log, \webshow(Data, M), Options).

clear :-
	wc_html(log, '', [clear(true)]).

webshow(Data, M) -->
	html(h4('Showing ~p'-[Data])),
	web_portray(Data, M).

web_portray(Var, _) -->
	{ var(Var) }, !,
	html(p('Unbound variable')).
web_portray(cell_range(Sheet, SX,SY, EX,EY), M) -->
	{ integer(SX), integer(SY), integer(EX), integer(EY) }, !,
	html(table(class(spreadsheet),
		   [ tr([td([])|\column_headers(SX,EX)])
		   | \table_rows(Sheet, SX,SY, EX,EY, M)
		   ])).
web_portray(cell(Sheet,X,Y), M) -->
	web_portray(cell_range(Sheet, X,Y, X,Y), M).
web_portray(table(_Id,_Type,_DS,_Headers,Union), M) -->
	web_portray(Union, M).
web_portray(sheet(Sheet), M) -->
	{ sheet_bb(M:Sheet, DS) }, !,
	web_portray(DS, M).
web_portray(List, M) -->
	{ is_list(List), !,
	  length(List, Len)
	},
	html(h2('List of ~D objects'-[Len])),
	web_portray_list(List, M).
web_portray(Block, M) -->
	{ atom(Block),
	  current_predicate(M:block/3),
	  M:block(Block, _Type, DS)
	},
	html(h2('Block ~p'-[Block])),
	web_portray(DS, M).
web_portray(_, _) -->
	html(p('No rules to portray')).

web_portray_list([], _) --> "".
web_portray_list([H|T], M) -->
	webshow(H, M), !,
	web_portray_list(T, M).

%%	column_headers(SX, EX)// is det.
%
%	Produce the column headers

column_headers(SX,EX) -->
	{ SX =< EX,
	  column_name(SX, Name),
	  X2 is SX+1
	},
	html(th(class(colname), Name)),
	column_headers(X2, EX).
column_headers(_, _) --> [].


%%	table_rows(+Sheet, +SX,+SY, +EX,+EY, +Module)// is det.

table_rows(Sheet, SX,SY, EX,EY, M) -->
	{ SY =< EY, !,
	  Y2 is SY+1
	},
	html(tr([ th(class(rowname),SY)
		| \table_row(Sheet, SY, SX, EX, M)
		])),
	table_rows(Sheet, SX,Y2, EX,EY, M).
table_rows(_, _,_, _,_, _) --> [].

table_row(Sheet, Y, SX,EX, M) -->
	{ SX =< EX, !,
	  X2 is SX+1
	},
	table_cell(Sheet, SX,Y, M),
	table_row(Sheet, Y, X2,EX, M).
table_row(_, _, _,_, _) --> [].

%%	table_cell(+Sheet, +SX, +SY, +Module)//

table_cell(Sheet, SX, SY, M) -->
	{ (   cell_type(Sheet, SX,SY, Type)
	  ->  true
	  ;   Type = empty
	  ),
	  findall(A, cell_class_attr(Sheet,SX,SY,Type,A, M), Classes),
	  (   Classes == []
	  ->  Attrs = []
	  ;   Attrs = [class(Classes)]
	  )
	},
	table_cell(Type, Sheet, SX, SY, Attrs, M).

cell_class_attr(_, _, _, Type, Type, _).
cell_class_attr(Sheet, X, Y, _, Class, M) :-
	(   cell_property(M:Sheet, X, Y, objects(_ObjId1,_ObjId2))
	->  Class = intables
	;   cell_property(M:Sheet, X, Y, block(ObjId)),
	    (   M:object_property(ObjId, color(C))
	    ->  color_class(C, Class)
	    ;   Class = intable
	    )
	).
cell_class_attr(Sheet, X, Y, _, derived, M) :-
	cell_formula(M:Sheet, X, Y, _).

color_class(1, c1).
color_class(2, c2).
color_class(3, c3).
color_class(4, c4).


%%	table_cell(+Sheet, +SX, +SY, +Style, +Module)//

table_cell(percentage, Sheet, SX, SY, Attrs, M) -->
	{ cell_value(M:Sheet, SX,SY, Value),
	  Val is Value*100
	}, !,
	html(td(Attrs, ['~3f%'-[Val]])).
table_cell(float, Sheet, SX, SY, Attrs, M) -->
	{ cell_value(M:Sheet, SX,SY, Value),
	  number(Value),
	  ndigits(Value, 5, V2)
	}, !,
	html(td(Attrs, [V2])).
table_cell(_, Sheet, SX, SY, Attrs, M) -->
	{ cell_value(M:Sheet, SX,SY, Value)
	}, !,
	(   { atomic(Value) }
	->  html(td(Attrs, Value))
	;   html(td(Attrs, '~q'-[Value]))
	).
table_cell(_, _, _, _, Attrs, _) -->
	html(td(Attrs, [])).

ndigits(F0, _, F) :-
	F0 =:= 0, !,
	F = F0.
ndigits(F0, N, F) :-
	Times is 10**max(1,N-round(log10(abs(F0)))),
	F is round(F0*Times)/Times.
