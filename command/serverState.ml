(** Copyright (c) 2016-present, Facebook, Inc.

    This source code is licensed under the MIT license found in the
    LICENSE file in the root directory of this source tree. *)

open Core

open Common

module Error = Analysis.Error
module Scheduler = Service.Scheduler
(* FIXME module Socket = CommandSocket*)


type client = {
  failures: int;
}

type connections = {
  socket: Caml.Unix.file_descr;
  persistent_clients: client Unix.File_descr.Table.t;
  file_notifiers: Caml.Unix.file_descr list;
}

type t = {
  deferred_requests: ServerProtocol.Request.t list;
  environment: (module Analysis.Environment.Handler);
  call_graph: (module Analysis.CallGraph.Handler);
  initial_errors: Analysis.Error.Hash_set.t;
  errors: (Error.t list) File.Handle.Table.t;
  handles: File.Handle.Set.t;
  lookups: Analysis.Lookup.t String.Table.t;
  scheduler: Scheduler.t;
  lock: Mutex.t;
  last_integrity_check: float;
  last_request_time: float;
  connections: connections ref;
}


let failure_threshold = 5


let stop_after_idle_for = 24.0 *. 60.0 *. 60.0 (* 1 day *)


let integrity_check_every = 60.0 (* 1 minute *)
