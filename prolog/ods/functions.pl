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

:- module(of_functions,
	  [ pmt/6			% +Rate, +Nper, +Pv, +Fv, +PayType, -Value
	  ]).

/** <module> Advanced Open Formula functions

This module provides the more  advanced   functions  defined by the Open
Formula specification.

@tbd	Implement most of them
@see	http://cgit.freedesktop.org/libreoffice/core/tree/sc/source/core/tool/interpr2.cxx
*/

%%	pmt(+Zins, +Zzr, +Bw, +Zw, +F, -Value)
%
%	@see http://docs.oasis-open.org/office/v1.2/os/OpenDocument-v1.2-os-part2.html#PMT
%	@see http://wiki.openoffice.org/wiki/Documentation/How_Tos/Calc:_PMT_function

pmt(Zins, Zzr, Bw, Zw, _, Value) :-
	Zins =:= 0.0, !,
	Rmz is (Bw+Zw)/Zzr,
	Value is -Rmz.
pmt(Zins, Zzr, Bw, Zw, F, Value) :-
	Term is (1.0+Zins)**Zzr,
	(   F > 0.0
	->  Rmz is (Zw*Zins/(Term-1.0)
		      + Bw*Zins/(1.0-1.0/Term)) / (1.0+Zins)
	;   Rmz is Zw*Zins/(Term-1.0)
	             + Bw*Zins/(1.0-1.0/Term)
	),
	Value is -Rmz.
