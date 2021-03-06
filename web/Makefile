TOP=..
#############################################################################
# Configuration section
#############################################################################

##############################################################################
# Variables
##############################################################################

INCLUDEDIRS= $(TOP)/commons \
 $(TOP)/h_program-lang/ \
 $(TOP)/h_visualization/ \
 $(TOP)/h_program-visual/ \
 $(TOP)/lang_php/parsing \
  $(TOP)/lang_php/analyze \
  $(TOP)/lang_php/analyze/foundation \

INCLUDES?=$(INCLUDEDIRS:%=-I %) $(SYSINCLUDES)

# for 'make annot'
LIBS_SHARED= -package deriving-ocsigen.syntax,js_of_ocaml.deriving.syntax \
  -syntax camlp4o
LIBS_SERVER= -thread -package tyxml,eliom,eliom.server \
  $(LIBS_SHARED)
LIBS_CLIENT= -package js_of_ocaml,eliom,eliom.client \
  -package eliom.syntax,js_of_ocaml.syntax -syntax camlp4o \
  $(LIBS_SHARED)
#,oclosure

OBJS_SERVER= \
 _server/common_server.cmo \
 _server/flag_web.cmo \
 _server/dump_server.cmo \
 _server/server.cmo \
 _server/codemap.cmo \
 _server/home.cmo \

# _server/global_db.cmo _server/htmlize_php2.cmo \
# _server/lxr_server.cmo \

OBJS_CLIENT= \
 _client/common_client.cmo \
 _client/canvas_helpers.cmo \
 _client/draw_macrolevel.cmo \
 _client/shared.cmo \
 _client/client.cmo \
 _client/codemap.cmo \
 _client/home.cmo \

LIBS_CLIENT2= $(TOP)/commons/commons.cma \
  $(TOP)/h_visualization/lib.cma

SYSLIBS_CLIENT=str.cma unix.cma

LIBS_SERVER2=
SYSLIBS_SERVER=

#to debug
#JSOPT=-jsopt -pretty -jsopt -noinline

##############################################################################
# Top rules
##############################################################################

all: var/app.cma var/static/app.js
#_oclosure

# server-side
var/app.cma: $(OBJS_SERVER)
	eliomc -a -o $@ $(SYSLIBS_SERVER) $(LIBS_SERVER2) $^

_server/htmlize_php2.cmo: htmlize_php2.ml
	eliomc -c $(INCLUDES) -package tyxml htmlize_php2.mli
	eliomc -c $(INCLUDES) -package tyxml $^


_server/home.cmo: home.eliom
	eliomc  -c -noinfer $(INCLUDES) $^
_server/codemap.cmo: codemap.eliom
	eliomc  -c -noinfer $(INCLUDES) $^


# client-side
var/static/app_oclosure.js: var/static/app.js
	oclosure_req $^

var/static/app.js: $(OBJS_CLIENT)
	js_of_eliom $(JSOPT) -o $@ $(SYSLIBS_CLIENT) $(LIBS_CLIENT2)  $^ -jsopt runtime2.js
#-package oclosure


_client/home.cmo: home.eliom
	eliomc  -infer $(INCLUDES) $^
	js_of_eliom $(JSOPT) -c $^
_client/codemap.cmo: codemap.eliom
	eliomc  -infer $(INCLUDES) $^
	js_of_eliom $(JSOPT) -c $(INCLUDES) $^


run:
	CAML_LD_LIBRARY_PATH=../external/ocamlbdb ocsigenserver -c ocsigen.conf

annot:
	ocamlfind ocamlc -dtypes -c $(LIBS_SHARED) shared.ml
	ocamlfind ocamlc -dtypes -c $(LIBS_SHARED) flag_web.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_SERVER) global_db.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_SERVER) htmlize_php2.mli
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_SERVER) htmlize_php2.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_SERVER) lxr_server.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_SERVER) dump_server.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_SERVER) server.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_CLIENT) common_client.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_CLIENT) canvas_helpers.mli
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_CLIENT) canvas_helpers.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_CLIENT) draw_macrolevel.mli
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_CLIENT) draw_macrolevel.ml
	ocamlfind ocamlc -dtypes -c $(INCLUDES) $(LIBS_CLIENT) client.ml
	rm -f *.cm*

clean::
	rm -rf _client _server

depend::
	eliomdep -client *.ml *.eliom > .depend
	eliomdep -server *.ml *.eliom >> .depend

# eliomdep does not handle dependencies between .eliom files for now
_server/home.cmo: _server/codemap.cmo

##############################################################################
# Generic ocaml rules
##############################################################################

_server/%.cmo: %.ml
	eliomc -c $(INCLUDES) $^

_server/%.cmi: %.mli
	eliomc -c $(INCLUDES) $^

_client/%.cmo: %.ml
	js_of_eliom $(JSOPT) -c $(INCLUDES) $^

_client/%.cmi: %.mli
	js_of_eliom $(JSOPT) -c $(INCLUDES) $^

-include .depend
