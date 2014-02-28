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

:- module(bisect,
	  [ bisect/4				% :Test, +Low, +High, -LowestFail
	  ]).

%%	bisect(:Test, +Low, +High, -LowestFail) is semidet.
%
%	True when LowestFail is the lowest  integer between Low and High
%	for which call(Test,LowestFail) fails.  Fails if call(Test,High)
%	succeeds.
%
%	This  predicate  assumes  that  there  is   a  Value  such  that
%	call(Test,X) is true for all X in [Low..Value) and false for all
%	X in [Value..High].

:- meta_predicate
	bisect(1, +, +, -).

bisect(Test, _, To, _) :-
	call(Test, To), !,
	fail.
bisect(Test, From, To, Last) :-
	bsect(Test, From, To, Last).

:- meta_predicate
	bsect(1, +, +, -).

bsect(Test, From, To, Last) :-
	Mid is (From+To)//2,
	(   call(Test, Mid)
	->  (   Mid+1 >= To
	    ->	Last = To
	    ;	bsect(Test, Mid, To, Last)
	    )
	;   (   Mid == From
	    ->	Last = From
	    ;	bsect(Test, From, Mid, Last)
	    )
	).
