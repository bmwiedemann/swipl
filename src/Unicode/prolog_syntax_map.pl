/*  $Id$

    Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        wielemak@science.uva.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2006, University of Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(prolog_syntax_map,
	  [ main/0,
	    write_syntax_map/2		% +File, +Options
	  ]).
:- use_module(library(debug), [assertion/1]).
:- use_module(library(lists), [member/2]).
:- use_module(library(option), [option/3]).
:- use_module(library('unicode/unicode_data'), [unicode_property/2]).
:- use_module(derived_core_properties, [unicode_derived_core_property/2]).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Create a C structure and  access   functions  for  classification of the
characters we need  for  realising  the   Prolog  syntax.  We  keep  the
definition of the first 128  ASCII   characters.  Characters  above that
needs to be classified as

	# id_start (csymf)
	May start an identifier.

	# id_continue (csym)
	May be used anywhere in identifier 

	# uppercase
	We need this to be able to distinquish variables from non-variables.

	# Separators
	We need this for classifying blank space

	# lowercase
	<not needed by Prolog>



Prolog symbols:
	#$&*+-./:<=>?@\^`~
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- multifile
	user:file_search_path/2.

user:file_search_path(unicode, '.').


main :-
	write_syntax_map('../pl-umap.c', []).


		 /*******************************
		 *	     C TABLES		*
		 *******************************/

%	write_unicode_collate_map(+File, +Options)
%	
%	Options supported are:
%	
%		# first_codepage [0]
%		Code page to start
%		
%		# last_codepage [255]
%		Code page to end.

write_syntax_map(File, Options) :-
	open(File, write, Out),
	call_cleanup(write_sort_map(Out, Options),
		     close(Out)).

write_sort_map(Out, Options) :-
	gen_tables(Tables, Options),
	write_header(Out, Options),
	forall((member(table(CP, Map), Tables),
		is_list(Map)),
	       write_codepage(Out, CP, Map)),
	write_map(Out, Tables, Options),
	write_footer(Out, Options).

write_codepage(Out, CP, Map) :-
	assertion(length(Map, 256)),
	cp_name(CP, CPN),
	format(Out, 'static const char ~w[256] =~n', [CPN]),
	format(Out, '{ ', []),
	map_entries(Map, 0, Out),
	format(Out, '~N};~n~n', []).

cp_name(CP, CPN) :-
	sformat(CPN, 'ucp0x~|~`0t~16r~2+', [CP]).
	       
map_entries([], _, _).
map_entries([H|T], I, Out) :-
	(   I == 0
	->  true
	;   0 =:= I mod 8
	->  format(Out, ',~n  ', [])
	;   format(Out, ', ', [])
	),
	format(Out, '~|0x~`0t~16r~2+', [H]),
	I2 is I + 1,
	map_entries(T, I2, Out).

write_map(Out, Tables, Options) :-
	option(last_codepage(Last), Options, 255),
	format(Out,
	       'static const char* const uflags_map[UNICODE_MAP_SIZE] =~n',
	       []),
	format(Out, '{ ', []),
	map_tables(0, Last, Tables, Out),
	format(Out, '~N};~n~n', []).

map_tables(CP, Last, _, _) :-
	CP > Last, !.
map_tables(CP, Last, Tables, Out) :-
	(   CP == 0
	->  true
	;   0 =:= CP mod 8
	->  format(Out, ',~n  ', [])
	;   format(Out, ', ', [])
	),
	memberchk(table(CP, Map), Tables),
	(   is_list(Map)
	->  cp_name(CP, CPN),
	    format(Out, '~w', [CPN])
	;   format(Out, '~|~tF(~16r)~7+', [Map])
	),
	CP2 is CP + 1,
	map_tables(CP2, Last, Tables, Out).


write_header(Out, Options) :-
	option(last_codepage(Last), Options, 255),
	Size is Last+1,
	format(Out, '/*  Generated file.  Do not edit!\n    \
		         Generated by Unicode/prolog_syntax_map.pl\n\
		     */~n~n', []),
	format(Out, '#define UNICODE_MAP_SIZE ~d~n', [Size]),
	format(Out, '#define F(c) (const char*)(c)~n~n', [Size]),
	(   flag_name(Name, Hex),
	    upcase_atom(Name, Up),
	    format(Out, '#define U_~w~t0x~16r~32|~n', [Up, Hex]),
	    fail ; true
	),
	format(Out, '~n~n', []).


write_footer(Out, _Options) :-
	format(Out,
	       'static int\n\
		uflagsW(int code)\n\
		{ int cp = (unsigned)code / 256;\n\
		\n  \
		  if ( cp < UNICODE_MAP_SIZE )\n  \
		  { const char *s = uflags_map[cp];\n    \
		    if ( s < (const char *)256 )\n      \
		      return (int)s;\n    \
		    return s[code&0xff];\n  \
		  }\n  \
		  return 0;\n\
		}\n\n', []).
%	format(Out,
%	       'static int\n\
%		uflagsA(int code)\n\
%		{ return ucp0x00[code&0xff];\n\
%		}\n\n', []).
	

		 /*******************************
		 *	       TABLES		*
		 *******************************/

%	gen_tables(-Tables, +Options)
%	
%	Table is of  the  format  below,   where  CodePage  is  the page
%	(0..255) for 16-bit Unicode and  ValueList   are  the values for
%	each character.
%
%		table(CodePage, ValueList)

gen_tables(Tables, Options) :-
	findall(table(CP,Map), table(CP, Map, Options), Tables).

table(CP, Map, Options) :-
	option(first_codepage(First), Options, 0),
	option(last_codepage(Last), Options, 255),
	between(First, Last, CP),	
	findall(M, char(CP, M, Options), Map0),
	flat_map(Map0, Map).

char(CP, Value, _Options) :-
	between(0, 255, I),
	Code is 256*CP+I,
	code_flags(Code, Value).

code_flags(Code, Value) :-
	findall(F, flag(Code, F), Fs),
	or(Fs, Value).

or([], 0).
or([H|T], F) :-
	or(T, F0),
	F is F0 \/ H.

flag(Code, Flag) :-
	code_flag(Code, Name),
	flag_name(Name, Flag).

flag_name(id_start,    0x01).
flag_name(id_continue, 0x02).
flag_name(uppercase,   0x04).
flag_name(lowercase,   0x08).
flag_name(separator,   0x10).

code_flag(C, id_start) :-    unicode_derived_core_property(C, id_start).
code_flag(C, id_continue) :- unicode_derived_core_property(C, id_continue).
code_flag(C, uppercase) :-   unicode_derived_core_property(C, uppercase).
code_flag(C, lowercase) :-   unicode_derived_core_property(C, lowercase).
code_flag(C, separator) :-
	unicode_property(C, general_category(Cat)),
	sep_cat(Cat).

sep_cat('Zs').
sep_cat('Zl').
sep_cat('Zp').

flat_map(Map0, Value) :-
	sort(Map0, [Value]), !.
flat_map(Map, Map).
