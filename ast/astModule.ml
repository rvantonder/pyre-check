(** Copyright (c) 2016-present, Facebook, Inc.

    This source code is licensed under the MIT license found in the
    LICENSE file in the root directory of this source tree. *)

open Core

open Common.Pyre

module Expression = AstExpression
module Access = Expression.Access
module Node = AstNode
module Statement = AstStatement


type t = {
  aliased_exports: (Access.t * Access.t) list;
  empty_stub: bool;
  wildcard_exports: Access.t list;
}
[@@deriving compare, eq, sexp]


let pp format { aliased_exports; empty_stub; wildcard_exports } =
  let aliased_exports =
    List.map aliased_exports
      ~f:(fun (source, target) -> Format.asprintf "%a -> %a" Access.pp source Access.pp target)
    |> String.concat ~sep:", "
  in
  let wildcard_exports =
    List.map wildcard_exports ~f:(Format.asprintf "%a" Access.pp)
    |> String.concat ~sep:", "
  in
  Format.fprintf format
    "[%s, empty_stub = %b, __all__ = [%s]]"
    aliased_exports
    empty_stub
    wildcard_exports


let show =
  Format.asprintf "%a" pp


let empty_stub { empty_stub; _ } =
  empty_stub


let wildcard_exports { wildcard_exports; _ } =  (* Rename to wildcard_exports *)
  wildcard_exports


let create ~qualifier ~stub ~statements =
  let aliased_exports =
    let aliased_exports { Node.value; _ } =
      let open Statement in
      match value with
      | Import { Import.from = Some from; imports } ->
          let from =
            match Access.show from with
            | ""
            | "." -> qualifier  (* From is `.`. *)
            | "builtins" -> []
            | _ -> from
          in
          let export { Import.name; alias } =
            let alias = Option.value ~default:name alias in
            let name = if Access.show alias = "*" then from else from @ name in
            (* The problem this bit solves is that we may generate an alias prefix <- prefix.rest
               after qualification, which would cause an infinite loop when folding over
               prefix.attribute. To avoid this, drop the prefix whenever we see that the
               qualified alias would cause a loop. *)
            if Access.is_strict_prefix ~prefix:(qualifier @ alias) name then
              alias, Access.drop_prefix ~prefix:qualifier name
            else
              alias, name
          in
          List.map ~f:export imports
      | Import { Import.from = None; imports } ->
          let export { Import.name; alias } =
            let alias = Option.value ~default:name alias in
            if Access.is_strict_prefix ~prefix:(qualifier @ alias) name then
              alias, Access.drop_prefix ~prefix:qualifier name
            else
              alias, name
          in
          List.map ~f:export imports
      | _ ->
          []
    in
    let filter_duplicates (sofar, visited) (alias, target) =
      if Set.mem visited alias then
        (sofar, visited)
      else
        (alias, target) :: sofar, Set.add visited alias
    in
    List.concat_map ~f:aliased_exports statements
    |> List.fold ~init:([], Access.Set.empty) ~f:filter_duplicates
    |> fst
  in
  let toplevel_public, dunder_all =
    let open Statement in
    let gather_toplevel (public_values, dunder_all) { Node.value; _ } =
      let filter_private =
        let is_public name =
          let dequalified = Access.drop_prefix ~prefix:qualifier name in
          if not (String.is_prefix ~prefix:"_" (Access.show dequalified)) then
            Some dequalified
          else
            None
        in
        List.filter_map ~f:is_public
      in
      match value with
      | Assign {
          Assign.target = { Node.value = Expression.Access target; _ };
          value = Some { Node.value = (Expression.List names); _ };
          _;
        }
        when Access.show target = "__all__" ->
          let to_access = function
            | { Node.value = Expression.String name; _ } -> Some (Expression.Access.create name)
            | _ -> None
          in
          public_values, Some (List.filter_map ~f:to_access names)
      | Assign { Assign.target = { Node.value = Expression.Access target; _ }; _ }
      | Stub (Stub.Assign { Assign.target = { Node.value = Expression.Access target; _ }; _ }) ->
          public_values @ (filter_private [target]), dunder_all
      | Class { Record.Class.name; _ }
      | Stub (Stub.Class { Record.Class.name; _ }) ->
          public_values @ (filter_private [name]), dunder_all
      | Define { Define.name; _ }
      | Stub (Stub.Define { Define.name; _ }) ->
          public_values @ (filter_private [name]), dunder_all
      | Import { Import.imports; _ } ->
          let get_import_name { Import.alias; name } = Option.value alias ~default:name in
          public_values @ (filter_private (List.map ~f:get_import_name imports)), dunder_all
      | _ ->
          public_values, dunder_all
    in
    List.fold ~f:gather_toplevel ~init:([], None) statements
  in
  {
    aliased_exports;
    empty_stub = stub && List.is_empty statements;
    wildcard_exports = (Option.value dunder_all ~default:toplevel_public);
  }


let aliased_export { aliased_exports; _ } access =
  Access.Map.of_alist aliased_exports
  |> (function
      | `Ok exports -> Some exports
      | _ -> None)
  >>= (fun exports -> Map.find exports access)


let in_wildcard_exports { wildcard_exports; _ } access =
  List.exists ~f:(Expression.Access.equal access) wildcard_exports


let wildcard_aliases { aliased_exports; _ } =
  let collect_wildcards (alias, target) =
    if Access.show alias = "*" then
      Some target
    else
      None
  in
  List.filter_map ~f:collect_wildcards aliased_exports
