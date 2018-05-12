(** Copyright (c) 2016-present, Facebook, Inc.

    This source code is licensed under the MIT license found in the
    LICENSE file in the root directory of this source tree. *)

open Core

open Ast
open Expression
open Common.Pyre
open Statement

module Resolution = AnalysisResolution
module Type = AnalysisType


let return_annotation ~define:({ Define.return_annotation; async; _ } as define) ~resolution =
  let annotation =
    Option.value_map
      return_annotation
      ~f:(Resolution.parse_annotation resolution)
      ~default:Type.Top
  in
  if async then
    Type.awaitable annotation
  else
  if Define.is_coroutine define then
    begin
      match annotation with
      | Type.Parametric { Type.name; parameters = [_; _; return_annotation] }
        when Identifier.show name = "typing.Generator" ->
          Type.awaitable return_annotation
      | _ ->
          Type.Top
    end
  else
    annotation


let apply_decorators ~define ~resolution =
  let return_annotation = return_annotation ~define ~resolution in
  match Define.has_decorator define "contextlib.contextmanager", return_annotation with
  | true, AnalysisType.Parametric { AnalysisType.name; parameters = [single_parameter] }
    when Identifier.show name = "typing.Iterator" ->
      {
        define with
        Define.return_annotation =
          Some
            (AnalysisType.Parametric {
                AnalysisType.name = Identifier.create "contextlib.GeneratorContextManager";
                parameters = [single_parameter];
              }
             |> Type.expression);
      }
  | _ ->
      define


let create defines ~resolution =
  let ({ Define.name; parent; _ } as define) = List.hd_exn defines in
  let open Type.Callable in
  let parameter { Node.value = { Ast.Parameter.name; annotation; value }; _ } =
    let name = Identifier.show name in
    let access =
      String.lstrip ~drop:(function | '*' -> true | _ -> false) name
      |> Access.create
    in
    let annotation =
      annotation
      >>| Resolution.parse_annotation resolution
      |> Option.value ~default:Type.Top
    in
    if String.is_prefix ~prefix:"**" name then
      Parameter.Keywords { Parameter.name = access; annotation; default = false }
    else if String.is_prefix ~prefix:"*" name then
      Parameter.Variable { Parameter.name = access; annotation; default = false }
    else
      Parameter.Named { Parameter.name = access; annotation; default = Option.is_some value }
  in
  let name = parent >>| (fun parent -> parent @ name) |> Option.value ~default:name in
  let implicit =
    if Define.is_class_method define then
      Type.Callable.Class
    else if Define.is_method define && not (Define.is_static_method define) then
      Type.Callable.Instance
    else
      Type.Callable.Function
  in
  let to_overload ({ Define.parameters; _ } as define) =
    {
      annotation = return_annotation ~define ~resolution;
      parameters = Defined (List.map ~f:parameter parameters);
    }
  in
  {
    kind = Named name;
    overloads = List.map ~f:to_overload defines;
    implicit;
  }
