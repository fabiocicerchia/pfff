TOP=../..
##############################################################################
# Variables
##############################################################################
TARGET=lib

-include $(TOP)/Makefile.config

SRC= ast_c.ml \
     lib_parsing_c.ml \
     parse_c.ml \
     test_parsing_c.ml unit_parsing_c.ml \

SYSLIBS= str.cma unix.cma 

# globals.cma is used only for Config. in unit_parse_cpp
LIBS=$(TOP)/commons/commons.cma \
 $(TOP)/globals/globals.cma \
 $(TOP)/h_program-lang/lib.cma \
 $(TOP)/lang_cpp/parsing/lib.cma

INCLUDEDIRS= \
 $(TOP)/commons $(TOP)/commons/ocamlextra \
 $(TOP)/commons/lib-sexp $(TOP)/commons/lib-json \
 $(TOP)/globals \
 $(TOP)/h_program-lang \
 $(TOP)/lang_cpp/parsing \

##############################################################################
# Generic variables
##############################################################################

-include $(TOP)/Makefile.common

##############################################################################
# Top rules
##############################################################################
all:: $(TARGET).cma
all.opt:: $(TARGET).cmxa

$(TARGET).cma: $(OBJS)
	$(OCAMLC) -a -o $(TARGET).cma $(OBJS)

$(TARGET).cmxa: $(OPTOBJS) $(LIBS:.cma=.cmxa)
	$(OCAMLOPT) -a -o $(TARGET).cmxa $(OPTOBJS)

$(TARGET).top: $(OBJS) $(LIBS)
	$(OCAMLMKTOP) -o $(TARGET).top $(SYSLIBS) $(LIBS) $(OBJS)

clean::
	rm -f $(TARGET).top

##############################################################################
# Generic rules
##############################################################################

##############################################################################
# Literate Programming rules
##############################################################################
