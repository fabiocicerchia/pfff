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
(* floats are the norm in graphics *)
open Common.ArithFloatInfix

open Figures
module CairoH = Cairo_helpers3

open Model3
module M = Model3
module Ctl = Controller3

module E = Database_code
module DM = Dependencies_matrix_code

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(* have a draw_labels.ml ? *) 

(* similar to highlight_code.ml *)
let color_of_node (_, kind) =
  match kind with
  | E.Function -> "gold"
  | E.Class _ -> "coral"
  | E.Module -> "chocolate"
  | E.Package -> "chocolate"
  | E.Type -> "YellowGreen"
  | E.Constant -> "pink"
  | E.Global -> "cyan"
  | E.Macro -> "pink1"
  | E.TopStmts -> raise Todo

  | E.Method _ -> "gold3"
  | E.Field -> "MediumPurple1"
  | E.ClassConstant -> raise Todo

  | E.Other s -> raise Todo

  | E.Dir | E.MultiDirs -> "SteelBlue2"
  | E.File -> "wheat"

let txt_of_node (s, kind) = 
  match kind with
  | E.Dir | E.File -> Common.basename s
  | E.Method _ | E.Field | E.Package | E.Class _ ->
      let xs = Common.split "[.]" s in
      Common.list_last xs
  | _ -> s

(* todo: style/font_of_node_kind? so put in bold directories *)

let line_width_of_depth l d =
  let h = l.height_cell in
  match d with
  | 0 -> h / 8.
  | 1 -> h / 20.
  | 2 -> h / 40.
  | _ -> h / 80.

let line_color_of_depth d =
  match d with
  | 0 -> "wheat"
  | 1 -> "grey80"
  | 2 -> "grey65"
  | 3 -> "grey50"
  | _ -> "grey30"

(*****************************************************************************)
(* Drawing helpers *)
(*****************************************************************************)

let draw_cells cr w ~interactive_regions =
  let l = M.layout_of_w w in

  for i = 0 to l.nb_elts -.. 1 do
    for j = 0 to l.nb_elts -.. 1 do
      (* the matrix is accessed as matrix.(row).(col), but here y corresponds
       * to the row, and x to the column, hence the association of j to x
       * and i to y.
       *)
      let x = (float_of_int j) * l.width_cell + l.x_start_matrix_left in
      let y = (float_of_int i) * l.height_cell + l.y_start_matrix_up in

      let rect = { 
        p = { x = x; y = y; };
        q = { x = x + l.width_cell; y = y + l.height_cell };
      } in
      Common.push2 (Cell (i, j), rect) interactive_regions;
      
      (* less: could also display intra dependencies *)
      if i = j then
        (* todo: heatmap? *)
        CairoH.fill_rectangle_xywh ~cr ~x ~y ~w:l.width_cell ~h:l.height_cell
          ~color:"wheat" ()
      else begin
        (* old: this is now done in draw_left_rows
         *  let _line_width = line_width_of_depth l depth in
         *  CairoH.draw_rectangle ~cr ~line_width ~color:"wheat" rect; 
         *)
        let n = w.m.DM.matrix.(i).(j) in
        if n > 0 then begin
          let txt = string_of_int n in
          let font_size = 
            match n with
            | _ when n <= 10 -> 
                l.width_cell / 2.
            | _ ->
                l.width_cell / (float_of_int (String.length txt))
          in
          CairoH.set_font_size cr font_size;
          (* todo: optimize? *)
          let extent = CairoH.text_extents cr txt in
          let tw = extent.Cairo.text_width in
          let th = extent.Cairo.text_height in
          
          let x = x + (l.width_cell / 2.) - (tw / 2.0) in
          let y = y + (l.height_cell / 2.) + (th / 2.0) in
          Cairo.move_to cr x y;
          CairoH.show_text cr txt;
        end;
      end
    done
  done;
  ()

let draw_left_rows cr w ~interactive_regions =
  let l = M.layout_of_w w in
  let font_size_default = min (l.height_cell/1.5) (l.x_start_matrix_left/10.) in
  CairoH.set_font_size cr font_size_default;


  let i = ref 0 in
  let rec aux depth tree =
    match tree with
    (* a leaf *)
    | DM.Node (node, []) ->
        (* draw box around label *)
        let x = float_of_int depth * l.width_vertical_label in
        let y = (float_of_int !i) * l.height_cell + l.y_start_matrix_up in
        let rect = { 
          p = { x = x; y = y; };
          q = { x = l.x_start_matrix_left; y = y + l.height_cell };
        } in
        let line_width = line_width_of_depth l depth in
        let color = line_color_of_depth depth in
        CairoH.draw_rectangle ~cr ~line_width ~color rect;

        Common.push2 (Row !i, rect) interactive_regions;

        (* draw horizontal lines around cells *)
        let rect2 = {
          p = { x = l.x_start_matrix_left; y = y; };
          q = { x = l.x_end_matrix_right; y = y + l.height_cell };
        } in
        CairoH.draw_rectangle ~cr ~line_width ~color rect2;
       
        (* draw vertical lines around cells *)
        let x' = (float_of_int !i) * l.width_cell + l.x_start_matrix_left in
        let y'  = l.y_start_matrix_up in
        let rect3 = {
          p = { x = x'; y = y'; };
          q = { x = x' + l.width_cell; y = l.y_end_matrix_down};
        } in
        CairoH.draw_rectangle ~cr ~line_width ~color rect3;

        (* old: let node = Hashtbl.find w.m.DM.i_to_name i in *)
        let color = color_of_node node in
        let txt = txt_of_node node in
        CairoH.set_source_color cr color ();
        CairoH.set_font_size cr font_size_default;
        let extent = CairoH.text_extents cr txt in
        let w = extent.Cairo.text_width in
        let width_for_label = l.x_start_matrix_left - x in
        (* todo: could try different settings until it works? like in cm? *)
        let font_size_final =
          if w > width_for_label 
          then (font_size_default / (w / width_for_label))
          else font_size_default
        in
        CairoH.set_font_size cr font_size_final;

        (* align text on the left *)
        let extent = CairoH.text_extents cr txt in
        let th = extent.Cairo.text_height in
        Cairo.move_to cr (x + 0.002) (y + (l.height_cell /2.) + (th / 2.0));
        CairoH.show_text cr txt;
        incr i

    (* a node, draw the label vertically *)
    | DM.Node (node, xs) ->
        let x = float_of_int depth * l.width_vertical_label in
        let y = (float_of_int !i) * l.height_cell + l.y_start_matrix_up in
        let n = float_of_int (List.length (DM.final_nodes_of_tree tree)) in
        let rect = {
          p = { x; y; };
          q = { x = x + l.width_vertical_label; y = y + n * l.height_cell};
        } in

        let line_width = line_width_of_depth l depth in
        CairoH.draw_rectangle ~cr ~line_width ~color:"SteelBlue2" rect;
        (* todo? push2 ?? interactive_regions *)

        let color = color_of_node node in
        let txt = txt_of_node node in
        CairoH.set_source_color cr color ();
        let font_size_default = 
          min (l.width_vertical_label/1.5) ((n * l.height_cell) /10.) in

        CairoH.set_font_size cr font_size_default;
        let extent = CairoH.text_extents cr txt in
        let w = extent.Cairo.text_width in

        let width_for_label = n * l.height_cell in
        (* todo: could try different settings until it works? like in cm? *)
        let font_size_final =
          if w > width_for_label 
          then (font_size_default / (w / width_for_label))
          else font_size_default
        in
        CairoH.set_font_size cr font_size_final;

        (* center the text *)
        let extent = CairoH.text_extents cr txt in
        let th = extent.Cairo.text_height in
        let tw = extent.Cairo.text_width in
        let angle = -. (pi / 2.) in
        Cairo.move_to cr 
          ((x + l.width_vertical_label / 2.) + (th / 2.0))
          (y + ((n * l.height_cell) /2.) + (tw / 2.0));
        Cairo.rotate cr ~angle;
        CairoH.show_text cr txt;
        Cairo.rotate cr ~angle:(-. angle);
        
        xs +> List.iter (aux (depth +.. 1))
  in
  (* use dm.config, not w.config which is not necessaraly ordered *)
  let config = w.m.DM.config in
  (match config with
  | DM.Node (_root, xs) -> xs +> List.iter (aux 0)
  )

let draw_up_columns cr w ~interactive_regions =
  let l = M.layout_of_w w in

  (* peh because it exercises the spectrum of high letters *)
  let extent = CairoH.text_extents cr "peh" in
  let _base_tw = extent.Cairo.text_width / 3. in
  let th = extent.Cairo.text_height in

  (* not -.. 1, cos we draw lines here, not rectangles *)
  for j = 0 to l.nb_elts do
    let x = (float_of_int j) * l.width_cell + l.x_start_matrix_left in
    let y = l.y_start_matrix_up in
    let rect = {
      (* fake rectangle *)
      p = { x = x; y = 0. };
      q = { x = x + l.width_cell; y = l.y_start_matrix_up };
    } in
    Common.push2 (Column j, rect) interactive_regions;

    CairoH.set_source_color ~cr ~color:"wheat" ();
    Cairo.move_to cr x y;
    (* because of the xy_ratio, this actually does not do a 45 deg line.
     * old: Cairo.line_to cr (x + (y_start_matrix_up / atan (pi / 4.)))  0.; 
     *)
    Cairo.line_to cr (x + (l.y_start_matrix_up / atan (pi / 2.8)))  0.; 
    Cairo.stroke cr;

    if j < l.nb_elts then begin
      let node = Hashtbl.find w.m.DM.i_to_name j in
      Cairo.move_to cr (x + (l.width_cell / 2.0) + (th / 2.0)) (y - 0.001);
      let angle = -. (pi / 4.) in
      Cairo.rotate cr ~angle:angle;
      let color = color_of_node node in
      let txt = txt_of_node node in
      CairoH.set_source_color cr color ();
      CairoH.show_text cr txt;
      Cairo.rotate cr ~angle:(-. angle);
    end;
  done;
  ()


(*****************************************************************************)
(* Drawing entry point *)
(*****************************************************************************)

(* assumes cr is setup with uniform coordinate system *)
let draw_matrix cr w =
  (* clear the screen *)
  CairoH.fill_rectangle_xywh ~cr ~x:0.0 ~y:0.0 ~w:xy_ratio ~h:1.0 
    ~color:"DarkSlateGray" ();

  let l = M.layout_of_w w in

  (* draw matrix enclosing rectangle *)
  CairoH.draw_rectangle ~cr ~line_width:0.001 ~color:"wheat"
    { p = { x = l.x_start_matrix_left; y = l.y_start_matrix_up };
      q = { x = l.x_end_matrix_right; y = 1.0 };
    };
  Cairo.select_font_face cr "serif"
    Cairo.FONT_SLANT_NORMAL Cairo.FONT_WEIGHT_BOLD;

  let interactive_regions = ref [] in


  draw_cells      cr w ~interactive_regions;
  draw_left_rows  cr w ~interactive_regions;
  draw_up_columns cr w ~interactive_regions;

  w.interactive_regions <- !interactive_regions;
  
  ()

(*****************************************************************************)
(* Painting entry point *)
(*****************************************************************************)

(* 'Paint' creates the cairo context and adjust the scaling if needed
 * and then call 'draw' functions.
 *)
let paint w =
  let cr = Cairo.create w.base in
  scale_coordinate_system cr w;
  draw_matrix cr w;
  !Ctl._refresh_drawing_area ();
  ()

(*****************************************************************************)
(* Events *)
(*****************************************************************************)

let recompute_matrix w =
  let config = M.config_of_path w.path w.model in
  let m = 
    Common.profile_code2 "Model.building matrix" (fun () -> 
      Dependencies_matrix_code.build config 
        (Some w.model.constraints) (Some w.model.full_matrix) w.model.g 
    )
  in
  !Ctl._set_title (DM.string_of_config_path w.path);
  w.m <- m;
  w.projection_cache <- Hashtbl.create 101;
  paint w;
  ()

let put_expand_just_before_last_focus_if_not_children n xs g =
  let rec aux xs =
    match xs with
    | [] -> [DM.Expand n]
    | x::xs ->
        (match x with
        | DM.Expand _ -> x::aux xs
        | DM.Focus (n2,style) ->
            let children = Graph_code.all_children n2 g in
            if not (List.mem n children)
            then (DM.Expand n)::x::xs
            else x::aux xs
        )
  in
  aux xs

let add_path x path g =
  match x with
  | DM.Focus _ -> path ++ [x]
  | DM.Expand (n) ->
      put_expand_just_before_last_focus_if_not_children n path g

let button_action da w ev =
  let (x, y) = GdkEvent.Button.x ev, GdkEvent.Button.y ev in
  let pt = { Cairo. x = x; y = y } in
  pr2 (spf "button action device coord: %f, %f" x y);

  let cr = Cairo.create w.overlay in
  M.scale_coordinate_system cr w;

  let pt2 = Cairo.device_to_user cr pt in
  let (x, y) = (pt2.Cairo.x, pt2.Cairo.y) in
  pr2 (spf "button action user coord: %f, %f" x y);

  (match M.find_region_at_user_point w ~x ~y with
  | None -> false
  | Some x ->
      (match x with
      | Row i -> 
            (match GdkEvent.get_type ev, GdkEvent.Button.button ev with
            | `TWO_BUTTON_PRESS, 1 ->
                pr2 (spf "double clicking on row i");
                let node = Hashtbl.find w.m.DM.i_to_name i in
                w.path <- add_path (DM.Expand node) 
                  w.path w.model.g;
                recompute_matrix w;
                true
            | `BUTTON_PRESS, 3 ->
                pr2 (spf "right clicking on row i");
                let node = Hashtbl.find w.m.DM.i_to_name i in
                w.path <- add_path (DM.Focus (node, DM.DepsOut)) 
                  w.path w.model.g;
                recompute_matrix w;
                true

            | `BUTTON_RELEASE, _ |  _ ->
                false
            )
      | Cell (i, j) -> 
            (match GdkEvent.get_type ev, GdkEvent.Button.button ev with
            | `BUTTON_PRESS, 1 ->
                pr2 (spf "clicking on cell (%d, %d)" i j);
                let deps = 
                  DM.explain_cell_list_use_edges 
                    w.projection_cache (i, j) w.m w.model.g in
                let str = 
                  deps +> List.map (fun (n1, n2) ->
                    spf "%s --> %s"
                      (Graph_code.string_of_node n1)  
                      (Graph_code.string_of_node n2)
                  )
                  +> Common.join "\n"
                in
                pr2 str;
                Gui.dialog_text ~text:str ~title:"Cell explaination";
                true

            | `BUTTON_PRESS, 3 ->
                pr2 (spf "right clicking on cell (%d, %d)" i j);
                if i = j
                then begin
                  let node = Hashtbl.find w.m.DM.i_to_name j in
                  w.path <- add_path (DM.Focus (node, DM.DepsInOut)) 
                    w.path w.model.g;
                  recompute_matrix w;
                  true
                end else
                  false

            | `BUTTON_RELEASE, _ | `TWO_BUTTON_PRESS, _ | _ ->
                false
            )

      | Column j ->
            (match GdkEvent.get_type ev, GdkEvent.Button.button ev with
            | `BUTTON_PRESS, 3 ->
                pr2 (spf "right clicking on column j");
                let node = Hashtbl.find w.m.DM.i_to_name j in
                w.path <- add_path (DM.Focus (node, DM.DepsIn)) 
                  w.path w.model.g;
                recompute_matrix w;
                true

            | _ -> false
            )
      )
  )

