(* -*- mode: Tuareg;-*-  *)
(* Filename:    Nominals.ml  *)
(* Authors:     lgm                                                     *)
(* Creation:    Thu Aug 21 23:55:54 2014  *)
(* Copyright:   Not supplied  *)
(* Description:  *)
(* ------------------------------------------------------------------------ *)

module type NOMINALS =
sig
  type symbol
  type term
  type nominal =
      Transcription of term
      | Symbol of symbol
  val comparator : nominal -> nominal -> bool
  val toString : nominal -> string
  val fresh : unit -> nominal
end 

module HashedNominals ( Nominal : NOMINALS ) : Hashtbl.HashedType =
  struct
    type t = Nominal.nominal
    let equal n1 n2 = ( Nominal.comparator n1 n2 )
    let hash n = Hashtbl.hash n
  end

