(* Yoann Padioleau
 *
 * Copyright (C) 2002-2011 Yoann Padioleau
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License (GPL)
 * version 2 as published by the Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * file license.txt for more details.
 *)
open Common

module Ast = Ast_cpp
module Flag = Flag_parsing_cpp
module TH = Token_helpers_cpp

module Parser = Parser_cpp
module Lexer = Lexer_cpp
module Semantic = Semantic_cpp

module PI = Parse_info
module Stat = Statistics_parsing

module Hack = Parsing_hacks_lib

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* 
 * A heuristic based C/C++/CPP parser.
 * 
 * See "Parsing C/C++ Code without Pre-Preprocessing - Yoann Padioleau, CC'09"
 * avalaible at http://padator.org/papers/yacfe-cc09.pdf
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

type program2 = toplevel2 list
     and toplevel2 = Ast.toplevel * info_item
      and info_item =  string * Parser.token list

let program_of_program2 xs = 
  xs +> List.map fst

let with_program2 f program2 = 
  program2 
  +> Common.unzip 
  +> (fun (program, infos) -> f program, infos)
  +> Common.uncurry Common.zip

(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)
let pr2, pr2_once = Common.mk_pr2_wrappers Flag_parsing_cpp.verbose_parsing

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let lexbuf_to_strpos lexbuf     = 
  (Lexing.lexeme lexbuf, Lexing.lexeme_start lexbuf)    

let token_to_strpos tok = 
  (TH.str_of_tok tok, TH.pos_of_tok tok)

let mk_info_item2 filename toks = 
  let s = 
    Common.with_open_stringbuf (fun (_pr, buf) ->
      toks +> List.iter (fun tok -> 
        match TH.pinfo_of_tok tok with
        | PI.OriginTok _ -> Buffer.add_string buf (TH.str_of_tok tok)
        | PI.ExpandedTok _ | PI.FakeTokStr _ -> ()
        | PI.Ab -> raise Impossible
      );
    )
  in
  (s, toks) 
let mk_info_item a b = 
  Common.profile_code "Parse_cpp.mk_info_item"  (fun () -> mk_info_item2 a b)

(*****************************************************************************)
(* Error diagnostic *)
(*****************************************************************************)

let error_msg_tok tok = 
  Parse_info.error_message_info (TH.info_of_tok tok)

let print_bad line_error (start_line, end_line) filelines  = 
  begin
    pr2 ("badcount: " ^ i_to_s (end_line - start_line));

    for i = start_line to end_line do 
      let line = filelines.(i) in 

      if i = line_error 
      then  pr2 ("BAD:!!!!!" ^ " " ^ line) 
      else  pr2 ("bad:" ^ " " ^      line) 
    done
  end

(*****************************************************************************)
(* Stats on what was passed/commentized  *)
(*****************************************************************************)

let commentized xs = xs +> Common.map_filter (function
  | Parser.TComment_Pp (cppkind, ii) -> 
      if !Flag.filter_classic_passed
      then 
        (match cppkind with
        | Token_cpp.CppOther -> 
            let s = Ast.str_of_info ii in
            (match s with
            | s when s =~ "KERN_.*" -> None
            | s when s =~ "__.*" -> None
            | _ -> Some (ii.PI.token)
            )
             
        | Token_cpp.CppDirective | Token_cpp.CppAttr | Token_cpp.CppMacro
            -> None
        | _ -> raise Todo
        )
      else Some (ii.PI.token)
      
  | Parser.TAny_Action ii ->
      Some (ii.PI.token)
  | _ -> 
      None
 )
  
let count_lines_commentized xs = 
  let line = ref (-1) in
  let count = ref 0 in
  begin
    commentized xs +>
    List.iter
      (function
      | PI.OriginTok pinfo 
      | PI.ExpandedTok (_,pinfo,_) -> 
          let newline = pinfo.PI.line in
          if newline <> !line
          then begin
            line := newline;
            incr count
          end
      | _ -> ());
    !count
  end

(* See also problematic_lines and parsing_stat.ml *)

(* for most problematic tokens *)
let is_same_line_or_close line tok =
  TH.line_of_tok tok =|= line ||
  TH.line_of_tok tok =|= line - 1 ||
  TH.line_of_tok tok =|= line - 2

(*****************************************************************************)
(* C vs C++ *)
(*****************************************************************************)
let fix_tokens_for_c xs =
  xs +> List.map (function
  | x when TH.is_cpp_keyword x ->
      let ii = TH.info_of_tok x in
      Parser.TIdent (Ast.str_of_info ii, ii)
  | x -> x
  )

(*****************************************************************************)
(* Lexing only *)
(*****************************************************************************)

(* called by parse below *)
let tokens2 file = 
 let table     = Parse_info.full_charpos_to_pos file in

 Common.with_open_infile file (fun chan -> 
  let lexbuf = Lexing.from_channel chan in
  try 
    let rec tokens_aux () = 
      let tok = Lexer.token lexbuf in
      (* fill in the line and col information *)
      let tok = tok +> TH.visitor_info_of_tok (fun ii -> 
        { ii with PI.token=
          (* could assert pinfo.filename = file ? *)
          match Parse_info.pinfo_of_info ii with
          |  PI.OriginTok pi ->
             PI.OriginTok (Parse_info.complete_parse_info file table pi)
          | PI.ExpandedTok (pi,vpi, off) ->
              PI.ExpandedTok(
                (Parse_info.complete_parse_info file table pi),vpi, off)
          | PI.FakeTokStr (s,vpi_opt) -> PI.FakeTokStr (s,vpi_opt)
          | PI.Ab -> raise Impossible
      })
      in

      if TH.is_eof tok
      then [tok]
      else tok::(tokens_aux ())
    in
    tokens_aux ()
  with
    | Lexer.Lexical s -> 
        failwith ("lexical error " ^ s ^ "\n =" ^ 
                  (Parse_info.error_message file (lexbuf_to_strpos lexbuf)))
    | e -> raise e
 )

let tokens a = 
  Common.profile_code "Parse_cpp.tokens" (fun () -> tokens2 a)

(*****************************************************************************)
(* Extract macros *)
(*****************************************************************************)

(* It can be used to to parse the macros defined in a macro.h file. It 
 * can also be used to try to extract the macros defined in the file 
 * that we try to parse *)
let extract_macros2 file = 
  Common.save_excursion Flag_parsing_cpp.verbose_lexing false (fun () -> 
    let toks = tokens (* todo: ~profile:false *) file in
    let toks = Parsing_hacks_define.fix_tokens_define toks in
    Pp_token.extract_macros toks
  )
let extract_macros a = 
  Common.profile_code_exclusif "Parse_cpp.extract_macros" (fun () -> 
    extract_macros2 a)

(*****************************************************************************)
(* Error recovery *)
(*****************************************************************************)

(* see parsing_recovery_cpp.ml *)

(*****************************************************************************)
(* Consistency checking *)
(*****************************************************************************)

(* see parsing_consistency_cpp.ml *)
      
(*****************************************************************************)
(* Helper for main entry point *)
(*****************************************************************************)

(* Hacked lex. This function use refs passed by parse. 
 * 'tr' means 'token refs'. This is used mostly to enable
 * error recovery (This used to do lots of stuff, such as
 * calling some lookahead heuristics to reclassify
 * tokens such as TIdent into TIdent_Typeded but this is
 * now done in a fix_tokens style in parsing_hacks_typedef.ml.
 *)
let rec lexer_function tr = fun lexbuf -> 
  match tr.PI.rest with
  | [] -> (pr2 "LEXER: ALREADY AT END"; tr.PI.current)
  | v::xs -> 
      tr.PI.rest <- xs;
      tr.PI.current <- v;
      tr.PI.passed <- v::tr.PI.passed;

      if !Flag.debug_lexer then pr2_gen v;

      if TH.is_comment v
      then lexer_function (*~pass*) tr lexbuf
      else v

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

(* todo?: pass it as a parameter to parse_program instead ? *) 
let (_defs : (string, Pp_token.define_body) Hashtbl.t ref)  = 
  ref (Hashtbl.create 101)

let init_defs file =     
  pr2 (spf "Using %s macro file" file);
  _defs := Common.hash_of_list (extract_macros file)

exception Parse_error of Parse_info.info

(* 
 * note: as now we go in two passes, there is first all the error message of
 * the lexer, and then the error of the parser. It is not anymore
 * interwinded.
 * 
 * !!!This function use refs, and is not reentrant !!! so take care.
 * It uses the _defs global defined above!!!!
 *)
let parse2 ?(c=false) file = 

  let stat = Statistics_parsing.default_stat file in
  let filelines = Common.cat_array file in

  (* -------------------------------------------------- *)
  (* call lexer and get all the tokens *)
  (* -------------------------------------------------- *)
  let toks_orig = tokens file in

  let toks = Parsing_hacks_define.fix_tokens_define toks_orig in
  let toks = if c then fix_tokens_for_c toks else toks in
  (* todo: _defs_builtins *)
  let toks = 
    try Parsing_hacks.fix_tokens ~macro_defs:!_defs toks
    with Token_views_cpp.UnclosedSymbol s ->
      pr2 (s);
      if !Flag.debug_cplusplus then raise (Token_views_cpp.UnclosedSymbol s)
      else toks
  in

  let tr = Parse_info.mk_tokens_state toks in

  let lexbuf_fake = Lexing.from_function (fun buf n -> raise Impossible) in

  let rec loop () =

    (* todo?: I am not sure that it represents current_line, cos maybe
     * tr.current partipated in the previous parsing phase, so maybe tr.current
     * is not the first token of the next parsing phase. Same with checkpoint2.
     * It would be better to record when we have a } or ; in parser.mly,
     *  cos we know that they are the last symbols of external_declaration2.
     *)
    let checkpoint = TH.line_of_tok tr.PI.current in

    (* bugfix: may not be equal to 'file' as after macro expansions we can
     * start to parse a new entity from the body of a macro, for instance
     * when parsing a define_machine() body, cf standard.h
     *)
    let checkpoint_file = TH.file_of_tok tr.PI.current in

    tr.PI.passed <- [];
    (* for some statistics *)
    let was_define = ref false in

    let elem = 
      (try 
          (* -------------------------------------------------- *)
          (* Call parser *)
          (* -------------------------------------------------- *)
          Parser.celem (lexer_function tr) lexbuf_fake
        with e -> 

          if not !Flag.error_recovery 
          then raise (Parse_error (TH.info_of_tok tr.PI.current));

          begin
            if !Flag.show_parsing_error then
              (match e with
              (* Lexical is not anymore launched I think *)
              | Lexer.Lexical s -> 
                pr2 ("lexical error " ^s^ "\n =" ^ error_msg_tok tr.PI.current)
              | Parsing.Parse_error -> 
                pr2 ("parse error \n = " ^ error_msg_tok tr.PI.current)
              | Semantic.Semantic (s, i) -> 
                pr2 ("semantic error " ^s^ "\n ="^ error_msg_tok tr.PI.current)
              | e -> raise e
              );

            let line_error = TH.line_of_tok tr.PI.current in

            let pbline =
              tr.PI.passed
              +> Common.filter (is_same_line_or_close line_error)
              +> Common.filter TH.is_ident_like
            in
            let error_info =(pbline +> List.map TH.str_of_tok), line_error in
            stat.Stat.problematic_lines <-
              error_info::stat.Stat.problematic_lines;

            (*  error recovery, go to next synchro point *)
            let (passed', rest') = 
              Parsing_recovery_cpp.find_next_synchro tr.PI.rest tr.PI.passed in
            tr.PI.rest <- rest';
            tr.PI.passed <- passed';

            tr.PI.current <- List.hd passed';

            (* <> line_error *)
            let checkpoint2 = TH.line_of_tok tr.PI.current in 
            let checkpoint2_file = TH.file_of_tok tr.PI.current in

            (* was a define ? *)
            let xs = tr.PI.passed +> List.rev +> Common.exclude TH.is_comment in
            (if List.length xs >= 2 
            then 
              (match Common.head_middle_tail xs with
              | Parser.TDefine _, _, Parser.TCommentNewline_DefineEndOfMacro _ 
                  -> 
                  was_define := true
              | _ -> ()
              )
            else pr2 "WIERD: length list of error recovery tokens < 2 "
            );
            
            (if !was_define && !Flag.filter_define_error
            then ()
            else 
              (* bugfix: *)
              (if (checkpoint_file = checkpoint2_file) && checkpoint_file = file
              then print_bad line_error (checkpoint, checkpoint2) filelines
              else pr2 "PB: bad: but on tokens not from original file"
              )
            );

            let info_of_bads = 
              Common.map_eff_rev TH.info_of_tok tr.PI.passed in 

            Ast.NotParsedCorrectly info_of_bads
          end
      )
    in

    (* again not sure if checkpoint2 corresponds to end of bad region *)
    let checkpoint2 = TH.line_of_tok tr.PI.current in
    let checkpoint2_file = TH.file_of_tok tr.PI.current in

    let diffline = 
      if (checkpoint_file = checkpoint2_file) && (checkpoint_file = file)
      then (checkpoint2 - checkpoint) 
      else 0
        (* TODO? so if error come in middle of something ? where the
         * start token was from original file but synchro found in body
         * of macro ? then can have wrong number of lines stat.
         * Maybe simpler just to look at tr.passed and count
         * the lines in the token from the correct file ?
         *)
    in
    let info = mk_info_item file (List.rev tr.PI.passed) in 

    (* some stat updates *)
    stat.Stat.commentized <- 
      stat.Stat.commentized + count_lines_commentized (snd info);
    (match elem with
    | Ast.NotParsedCorrectly xs -> 
        if !was_define && !Flag.filter_define_error
        then stat.Stat.commentized <- stat.Stat.commentized + diffline
        else stat.Stat.bad     <- stat.Stat.bad     + diffline

    | _ -> stat.Stat.correct <- stat.Stat.correct + diffline
    );

    (match elem with
    | Ast.FinalDef x -> [(Ast.FinalDef x, info)]
    | xs -> (xs, info):: loop () (* recurse *)
    )
  in
  let v = loop() in
  let v = with_program2 Parsing_consistency_cpp.consistency_checking v in
  (v, stat)

let parse ?c file  = 
  Common.profile_code "Parse_cpp.parse" (fun () -> 
    try 
      parse2 ?c file
    with Stack_overflow ->
      pr2 (spf "PB stack overflow in %s" file);
      [(Ast.NotParsedCorrectly [], ("", []))], {Stat.
        correct = 0;
        bad = Common.nblines_with_wc file;
        filename = file;
        have_timeout = true;
        commentized = 0;
        problematic_lines = [];
      }
  )

let parse_program file = 
  let (ast2, _stat) = parse file in
  program_of_program2 ast2
