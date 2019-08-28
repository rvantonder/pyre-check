# Copyright (c) 2016-present, Facebook, Inc.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import argparse
from typing import List, Optional  # noqa

from .. import log
from ..configuration import Configuration
from ..filesystem import AnalysisDirectory
from .check import Check


class Analyze(Check):
    NAME = "analyze"  # type: str

    def __init__(
        self,
        arguments: argparse.Namespace,
        configuration: Configuration,
        analysis_directory: AnalysisDirectory,
    ) -> None:
        super(Analyze, self).__init__(arguments, configuration, analysis_directory)
        self._analysis = arguments.analysis  # type: str
        self._taint_models_path = (
            arguments.taint_models_path or configuration.taint_models_path
        )  # type: List[str]
        self._save_results_to = arguments.save_results_to  # type: Optional[str]
        self._dump_call_graph = arguments.dump_call_graph  # type: bool

    def _flags(self) -> List[str]:
        flags = super()._flags()
        flags.extend(["-analysis", self._analysis])
        if self._taint_models_path:
            for path in self._taint_models_path:
                flags.extend(["-taint-models", path])
        save_results_to = self._save_results_to
        if save_results_to:
            flags.extend(["-save-results-to", save_results_to])
        if self._dump_call_graph:
            flags.extend(["-dump-call-graph"])
        return flags

    def _run(self, retries: int = 1) -> None:
        self._analysis_directory.prepare()
        result = self._call_client(command=self.NAME)
        result.check()
        log.stdout.write(result.output)
