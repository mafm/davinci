(* -*- mode: Tuareg;-*-  *)
(* Filename:    REPL.ml  *)
(* Authors:     lgm                                                     *)
(* Creation:    Thu Sep  4 02:11:59 2014  *)
(* Copyright:   Not supplied  *)
(* Description:  *)
(* ------------------------------------------------------------------------ *)

open Lexing
open Abscacao
open Exceptions
open Evaluator
open Monad
open Stage1
open Symbols
open Cfg
open BatChar

module type REPLS =
sig
  module Pipeline : ASTXFORMS

  val parse : in_channel -> Abscacao.request
  val showTree : Abscacao.request -> string
  val print_rslt : Pipeline.model_value -> string
  val eval : Pipeline.model_term -> Pipeline.model_value Pipeline.REval.monad
  val read_eval_print_loop : unit -> unit
end

module type REPLFUNCTOR =
  functor ( M : MONAD ) ->
sig
  module Pipeline : ( ASTXFORMS with type 'a REval.monad = 'a M.monad )

  val parse : in_channel -> Abscacao.request
  val showTree : Abscacao.request -> string
  val print_rslt : Pipeline.model_value -> string
  val eval : Pipeline.model_term -> Pipeline.model_value Pipeline.REval.monad
  val read_eval_print_loop : unit -> unit
end

module REPL : REPLFUNCTOR =
  functor ( M : MONAD ) ->
struct
  module Pipeline : ( ASTXFORMS with type 'a REval.monad = 'a M.monad )
    = ASTXFORM( M )

  let parse (c : in_channel) : Abscacao.request = 
    Parcacao.pRequest Lexcacao.token (Lexing.from_channel c)

  let showTree (t : Abscacao.request) : string = 
    "[Abstract syntax]\n\n" ^ (fun x -> Showcacao.show (Showcacao.showRequest x)) t ^ "\n\n" ^
      "[Linearized tree]\n\n" ^ Printcacao.printTree Printcacao.prtRequest t ^ "\n"

  let showAST (t : Abscacao.expr) : string = 
    "[Abstract syntax]\n\n" ^ (fun x -> Showcacao.show (Showcacao.showExpr x)) t ^ "\n\n" ^
      "[Linearized tree]\n\n" ^ Printcacao.printTree Printcacao.prtExpr t ^ "\n"

  let print_rslt v =
    match v with 
        Pipeline.REval.ReflectiveValue.Ground( Pipeline.REval.ReflectiveValue.Boolean( true ) ) ->
          "true"
      | Pipeline.REval.ReflectiveValue.Ground( Pipeline.REval.ReflectiveValue.Boolean( false ) ) ->
          "false"
      | Pipeline.REval.ReflectiveValue.Ground( Pipeline.REval.ReflectiveValue.String( s ) ) ->
          ( "\"" ^ s ^ "\"" )
      | Pipeline.REval.ReflectiveValue.Ground( Pipeline.REval.ReflectiveValue.Integer( i ) ) ->
          ( string_of_int i )
      | Pipeline.REval.ReflectiveValue.Ground( Pipeline.REval.ReflectiveValue.Double( d ) ) ->
          ( string_of_float d )
      | Pipeline.REval.ReflectiveValue.Ground( Pipeline.REval.ReflectiveValue.Reification( t ) ) ->
          raise ( NotYetImplemented "render reification" )
      | Pipeline.REval.ReflectiveValue.Closure( p, t, e ) ->
          "#<closure>"
      | Pipeline.REval.ReflectiveValue.BOTTOM ->
          raise ( NotYetImplemented "render bottom" )
      | Pipeline.REval.ReflectiveValue.UNIT ->
          "()"

  let eval m_term =
    let p = ( Pipeline.REval.initial_prompt() ) in
    let m = ( Pipeline.REval.initial_meta_ktn() ) in
    let e = ( Pipeline.REval.init_env ) in
    let x_str = (* fresh variable string *)
      ( Pipeline.REval.ReflectiveNominal.toString 
          ( Pipeline.REval.ReflectiveNominal.fresh() ) ) in
    let x_ident =
      ( Pipeline.REval.ReflectiveTerm.Identifier
          ( Pipeline.REval.ReflectiveNominal.Symbol ( Symbols.Opaque x_str ) ) ) in
    let x_fml = 
      ( Pipeline.REval.ReflectiveTerm.Variable x_ident ) in
    let x_mntn = 
      ( Pipeline.REval.ReflectiveTerm.Calculation
          ( Pipeline.REval.ReflectiveTerm.Mention x_ident ) ) in
    let id =
      ( Pipeline.REval.ReflectiveValue.Closure ( x_fml, x_mntn, e ) ) in
    let mk = ( Pipeline.REval.init_k id e m p ) in      
      ( M.m_bind
          mk
          ( fun k ->
            ( Pipeline.REval.reduce
                m_term
                e (* BUGBUG -- lgm -- this assumes no builtin fns *)
                p
                k
                m
                ( p + 1 ) ) ) )

  let evaluate_expression ast =
    let desugared_ast = ( Pipeline.desugar ast ) in
    let term = ( Pipeline.expr_to_term desugared_ast ) in
      ( eval term )

  let report v =
    begin
      ( M.m_bind
          v
          ( fun nrml ->
            print_string ( print_rslt nrml );
            ( M.m_unit nrml ) ) );
      print_newline ();
      flush stdout
    end

  let read_eval_print_loop () = 
    (* let dbg = ref false in *)    
    let rslt = ref true in
    let show_tree = 
      CacaoScriptConfig.show_parse_tree() in
    let channel =
      ( match CacaoScriptConfig.file_to_read() with
          Some( file_name ) -> ( open_in file_name )
        | None -> stdin )
    in
      print_string " *** Cacao Top Level version 0.01 *** \n";

      try
        (while (!rslt)
          do	  
	    print_string "> ";
	    flush stdout;
	    let ast = parse channel in            
              begin	                      
                ( match show_tree with
                    true ->
                      let astStr = showTree ast in          
                        print_string ( "ast = " ^ ( astStr ^ ".\n" ) )
                  | _ -> () );
                print_newline ();
                flush stdout;
                ( match ast with 
                    Evaluation( expr_ast ) ->
                      let v = ( evaluate_expression expr_ast ) in
                        ( report v )
                  | TypeCheck( expr_ast, type_ast ) ->
                      raise ( NotYetImplemented "TypeCheck" )
                  | ModelCheck( expr_ast, form_ast ) ->
                      raise ( NotYetImplemented "ModelCheck" )
                  | OuterShell( osreq ) ->
                      raise ( NotYetImplemented "OuterShell" )
                  | InnerShell( isreq ) ->
                      match isreq with
                          ExitRequest -> rslt := false
                        | DesugarRequest( ast ) ->
                            ( print_string ( showAST ( Pipeline.desugar ast ) ) )
                        | ParseRequest( s ) ->
                            raise ( NotYetImplemented "inner shell parse request" )
                        | _ -> raise ( NotYetImplemented "other inner shell requests" ) )
              end
          done)
      with e ->
        begin
          print_string "caught exception...\n"; 
          print_string (Printexc.to_string e);
          print_string "\n exiting";
          print_newline ();
          flush stdout;
          ()
        end
end
