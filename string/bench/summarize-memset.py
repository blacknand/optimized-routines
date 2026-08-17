#!/usr/bin/env python3

import argparse
import json
from pathlib import Path

# BASELINE = "__memset_generic"
BASELINE = "__memset_generic"
RUN_COUNT = 5

BENCHMARKS = (
    "bench-memset",
    # "bench-memset-large",
    # "bench-memset-random",
    # "bench-memset-zero",
    # "bench-memset-zero-large",
)

def load_run(path):
    with path.open("r", encoding="utf-8") as input_file:
        document = json.load(input_file)

    try:
        function_data = document["functions"]["memset"]
        ifuncs = function_data["ifuncs"]
        results = function_data["results"]
    except (KeyError, TypeError) as error:
        raise ValueError(
            f"{path} does not have the expected glibc benchmark structure"
        ) from error

    if not isinstance(ifuncs, list):
        raise ValueError(f"{path}: 'ifuncs' must be a list")

    if not all(isinstance(name, str) for name in ifuncs):
        raise ValueError(f"{path}: every implementation name must be a string")

    if not isinstance(results, list):
        raise ValueError(f"{path}: 'results' must be a list")

    for test_number, result in enumerate(results):
        if not isinstance(result, dict):
            raise ValueError(
                f"{path}: test {test_number} must be a JSON object"
            )

        timings = result.get("timings")

        if not isinstance(timings, list):
            raise ValueError(
                f"{path}: test {test_number} has no timings list"
            )

        if len(timings) != len(ifuncs):
            raise ValueError(
                f"{path}: test {test_number} has "
                f"{len(timings)} timings but {len(ifuncs)} implementations"
            )

        if not all(type(timing) in (int, float) for timing in timings):
            raise ValueError(
                f"{path}: test {test_number} contains a non-numeric timing"
            )

    return function_data

def test_metadata(result):
    return {
        key: value
        for key, value in result.items()
        if key != "timings"
    }

def validate_run_series(benchmark, runs):
    reference = runs[0]

    if BASELINE not in reference["ifuncs"]:
        raise ValueError(
            f"{benchmark}: baseline {BASELINE} is missing"
        )

    reference_metadata = [
        test_metadata(result)
        for result in reference["results"]
    ]

    for run_number, current_run in enumerate(runs[1:], start=2):
        if current_run["ifuncs"] != reference["ifuncs"]:
            raise ValueError(
                f"{benchmark}: implementation order differs in run {run_number}"
            )

        current_metadata = [
            test_metadata(result)
            for result in current_run["results"]
        ]

        if current_metadata != reference_metadata:
            raise ValueError(
                f"{benchmark}: test cases differ in run {run_number}"
            )

def load_all_runs(results_directory):
    benchmark_runs = {}

    for benchmark in BENCHMARKS:
        runs = []

        for run_number in range(1, RUN_COUNT + 1):
            filename = f"{benchmark}.run-{run_number}.out"
            path = results_directory / filename
            runs.append(load_run(path))

        validate_run_series(benchmark, runs)
        benchmark_runs[benchmark] = runs

    return benchmark_runs

"""
Variants:
    + The result directory contains:
        + Five bench-memset runs
        + Five bench-memset-random runs
        ...
      Each file contains measurements for different lengths, alignments
      and fill values.

Data from the glibc benchmark JSON output:
    + 1 run of a specific benchmark = 1 run-n.out file
    + For each run, there are n results (memset calls/tests) where each result contains an array
      of timing results for each implementation. For example, if there are 4 memset implementations, then
      there are 4 timing results in the array.
    + 
"""

def summarize_benchmark_family(runs, candidate):
    """Calculate candidate-versus-baseline averages for each run and family."""
    if not runs:
        raise ValueError("cannot summarize a benchmark family with no runs")

    ifuncs = runs[0]["ifuncs"]

    try:
        candidate_index = ifuncs.index(candidate)
        baseline_index = ifuncs.index(BASELINE)
    except ValueError as error:
        raise ValueError(
            f"benchmark family must contain {candidate} and {BASELINE}"
        ) from error

    run_summaries = []
    family_candidate_total = 0.0
    family_baseline_total = 0.0

    for run_number, run in enumerate(runs, start=1):
        results = run["results"]

        if not results:
            raise ValueError(f"run {run_number} contains no results")

        candidate_total = 0.0
        baseline_total = 0.0

        for result in results:
            candidate_total += result["timings"][candidate_index]
            baseline_total += result["timings"][baseline_index]

        # The average for the candidate and the baseline are calculated the same way
        result_count = len(results)
        candidate_average = candidate_total / result_count
        baseline_average = baseline_total / result_count

        if baseline_average == 0:
            raise ValueError(f"run {run_number} has a zero baseline average")

        """
        The baseline is the reference implementation against which the specified routine implementation
        is measured against. The timings are as follows:
            + Positive: candidate is slower than baseline
            + Negative: candidate is faster
            + Zero: equal average timing
        """
        percentage = (
            (candidate_average - baseline_average)
            / baseline_average
            * 100
        )

        run_summaries.append(
            {
                "run": run_number,
                "candidate_average": candidate_average,
                "baseline_average": baseline_average,
                "percentage": percentage,
            }
        )

        family_candidate_total += candidate_average
        family_baseline_total += baseline_average

    run_count = len(runs)
    family_candidate_average = family_candidate_total / run_count
    family_baseline_average = family_baseline_total / run_count

    if family_baseline_average == 0:
        raise ValueError("benchmark family has a zero baseline average")

    family_percentage = (
        (family_candidate_average - family_baseline_average)
        / family_baseline_average
        * 100
    )

    return {
        "runs": run_summaries,
        "family": {
            "candidate_average": family_candidate_average,
            "baseline_average": family_baseline_average,
            "percentage": family_percentage,
        },
    }

def main():
    parser = argparse.ArgumentParser(
        usage="%(prog)s RESULTS_DIRECTORY --routine=<routine>"
    )
    parser.add_argument("results_directory", type=Path)
    parser.add_argument(
        "--routine",
        required=True,
        help="memset implementation to compare against the NEON baseline",
    )
    arguments = parser.parse_args()

    results_directory = arguments.results_directory
    candidate = arguments.routine

    if not results_directory.is_dir():
        raise SystemExit(
            f"results directory does not exist: {results_directory}"
        )

    benchmark_runs = load_all_runs(results_directory)

    for benchmark, runs in benchmark_runs.items():
        result_count = len(runs[0]["results"])
        implementation_count = len(runs[0]["ifuncs"])

        print(
            f"{benchmark}: loaded {len(runs)} runs, "
            f"{result_count} results and "
            f"{implementation_count} implementations"
        )

        family_summary = summarize_benchmark_family(runs, candidate)

        for run_summary in family_summary["runs"]:
            print(
                f"  Run {run_summary['run']}: "
                f"{candidate} average = "
                f"{run_summary['candidate_average']:.2f}, "
                f"{BASELINE} average = "
                f"{run_summary['baseline_average']:.2f}, "
                f"difference = {run_summary['percentage']:.2f}%"
            )

        overall = family_summary["family"]
        print(
            f"  Family: {candidate} average = "
            f"{overall['candidate_average']:.2f}, "
            f"{BASELINE} average = {overall['baseline_average']:.2f}, "
            f"difference = {overall['percentage']:.2f}%"
        )

if __name__ == "__main__":
    main()
