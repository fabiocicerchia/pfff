(* Yoann Padioleau
 *
 * Copyright (C) 2012 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
open Common

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
 * history:
 *  - was in main_codestat.ml
 *)


(*****************************************************************************)
(* Types *)
(*****************************************************************************)

type info_txt = 
  (string * string list) list

(* todo: a tree! or graph when have tags! *)
type info_txts = unit

(*****************************************************************************)
(* IO *)
(*****************************************************************************)

let load file =
  let xs = 
    Common.cat file
    +> List.map (Str.global_replace (Str.regexp "#.*") "" )
    +> List.map (Str.global_replace (Str.regexp "\\* -----.*") "" )
    +> Common.exclude Common.is_blank_string 
  in
  let xxs = Common.split_list_regexp "^\\* " xs in
  xxs +> List.map (fun (s, body) ->
    if s =~ "^\\* \\([^ ]+\\)[ \t]*$"
    then 
      let dir = Common.matched1 s in
      dir, body
    else 
      failwith (spf "wrong format in %s, entry: %s" file s)
  )

