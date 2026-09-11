#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
from statistics import fmean, median

BENCHMARK = "bench-memset"
RUN_COUNT = 5
WORST_RESULT_COUNT = 5
RUNS = {}

def load_run(path):
    """
    Return an individual runs meta-data and results from the glibc benchmark
    runs[0] = {
        "bench-variant": "default",
        "ifuncs": ["generic_memset"],
        "results": [
            result_1,
            result_2,
            # ...
            result_1444,
        ],
    }
    """
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

    # All of the below is just generic error checking
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
    # Create a new dictionary contianing everything except timings
    return {
        key: value
        for key, value in result.items()
        if key != "timings"
    }


def validate_run_series(label, runs):
    if not runs:
        raise ValueError(f"{label}: no runs were loaded")

    # Run 1 is the reference for which runs 2-5 are compared against
    reference = runs[0]
    if len(reference["ifuncs"]) != 1:
        raise ValueError(
            f"{label}: expected one implementation, "
            f"found {len(reference['ifuncs'])}"
        )

    reference_metadata = [
        test_metadata(result)
        for result in reference["results"]
    ]

    # Ensure that the meta data for the candidate runs and baseline runs match
    for run_number, current_run in enumerate(runs[1:], start=2):
        if current_run["ifuncs"] != reference["ifuncs"]:
            raise ValueError(
                f"{label}: implementation differs in run {run_number}"
            )

        current_metadata = [
            test_metadata(result)
            for result in current_run["results"]
        ]

        # Reject if the metadata differs, not the timing.
        # The timing can be different (expected) but the metadata cannot
        if current_metadata != reference_metadata:
            raise ValueError(
                f"{label}: test cases differ in run {run_number}"
            )

"""
TODO:
    Major refactoring. Check notes. I want to have a global KV store with each full run
    mapped to an array off all of the runs within that full run. A function for summarising the data
    across the entire global data structure will therefore likely be the current summarize-benchmark_family
    routine but just heavily refactored. Check notepad.
"""

def load_all_runs(run_group_dir):
    """Load all runs for a benchmark family"""

    """
    bench_run-2/__memset_generic/run-4.out means
    for each bench_run-<n> in run_group_dir
        for each implementation_dir in bench_run-<n>
            for each .out run file in implementation_dir
                <represents individual run for a specific
                 memset implementation within a whole bench_run>
    """
    loaded_runs = {}

    for bench_run_dir in sorted(run_group_dir.iterdir()):
        if not bench_run_dir.is_dir():
            continue

        for implementation_dir in sorted(bench_run_dir.iterdir()):
            if not implementation_dir.is_dir():
                continue

            implementation_name = implementation_dir.name
            bench_run_name = bench_run_dir.name
            run_files = sorted(implementation_dir.glob("run-*.out"))

            if len(run_files) != RUN_COUNT:
                raise ValueError(
                    f"{implementation_dir}: expected {RUN_COUNT} run files, "
                    f"found {len(run_files)}"
                )

            individual_runs = {}
            run_series = []

            for run_file in run_files:
                loaded_run = load_run(run_file)

                if loaded_run["ifuncs"] != [implementation_name]:
                    raise ValueError(
                        f"{run_file}: implementation name does not match "
                        f"directory {implementation_name}"
                    )

                individual_runs[run_file.stem] = loaded_run
                run_series.append(loaded_run)

            validate_run_series(
                f"{implementation_name}/{bench_run_name}",
                run_series,
            )
            loaded_runs.setdefault(implementation_name, {})[
                bench_run_name
            ] = individual_runs

    if not loaded_runs:
        raise ValueError(f"{run_group_dir}: no benchmark runs were found")

    RUNS.clear()
    RUNS.update(loaded_runs)
    return RUNS

    # # Each bench-run<n>
    # RUNS[routine: {}]
    # for n, dir in enumerate(run_group_dir):
    #     routine_kv = {
    #         f"bench-run-{n}": {}
    #     }
    #     RUNS[routine[[dir]]] = routine_kv
    #     if dir.is_dir():
    #         # Each memset impl
    #         for sub_dir in dir:
    #             # Need to know the name of the directory
    #             if sub_dir != routine: continue
    #             sub_runs = []
    #             individual_run = {f"run-{n}": sub_runs}
    #             for run_number in range(1, RUN_COUNT + 1):
    #                 filename = f"{routine}.{dir}.run-{run_number}.out"
    #                 path = run_group_dir / dir / sub_dir / filename
    #                 # Individual path
    #                 sub_runs.append(load_run(path))
    #             RUNS[routine[f"bench-run-{n}"]] = individual_run
    #             validate_run_series(routine, sub_runs)
    # return RUNS

# RUNS = {
#     "__memset_sve_zva64": {
#         "bench-run-<n>": {
#             "individual-run-<n>": {
#                 [<result from load_run],
#                 [<other result from load_run]
#             }
#         }
#     },
#     "__memset_aarch64_sve2": {
#         "bench-run-<n>": {
#             "individual-run-<n>": {
#                 [<result from load_run],
#                 [<other result from load_run]
#             }
#         }
#     }
# }

def validate_matching_series(candidate_runs, baseline_runs):
    if len(candidate_runs) != len(baseline_runs):
        raise ValueError(
            "candidate and baseline contain different numbers of runs"
        )

    # For run number, and a pair of the baseline test and candidate test
    for run_number, (candidate_run, baseline_run) in enumerate(
        zip(candidate_runs, baseline_runs), start=1
    ):
        # For each run, check candidate and baseline meta data match
        candidate_metadata = [
            test_metadata(result)
            for result in candidate_run["results"]
        ]
        baseline_metadata = [
            test_metadata(result)
            for result in baseline_run["results"]
        ]

        if candidate_metadata != baseline_metadata:
            raise ValueError(
                f"candidate and baseline test cases differ in run {run_number}"
            )


def percentage_difference(candidate_timing, baseline_timing, context):
    """
    + Negative means the candidate is faster
    + Zero means equal timing
    + Positive means the candidate is slower
    """
    if baseline_timing == 0:
        raise ValueError(f"{context} has a zero baseline timing")

    return (
        (candidate_timing - baseline_timing)
        / baseline_timing
        * 100
    )


def summarize_benchmark_family(candidate_runs, baseline_runs):
    """
    Return five individual run summaries and one overall family summary
    """
    if not candidate_runs or not baseline_runs:
        raise ValueError("candidate and baseline runs must not be empty")

    # Ensure the candidate and baseline tests match first
    validate_matching_series(candidate_runs, baseline_runs)

    candidate_name = candidate_runs[0]["ifuncs"][0]
    baseline_name = baseline_runs[0]["ifuncs"][0]
    run_summaries = []
    all_run_results = []

    # These summaries describe each individual run.  Each test receives equal
    # weight because its percentage is calculated before the run average.
    for run_number, (candidate_run, baseline_run) in enumerate(
        zip(candidate_runs, baseline_runs), start=1
    ):
        # This will store one percentage for each of the current runs 1444 tests
        run_percentages = []

        # Calculate the run percentage difference for each result horizontally
        for test_number, (candidate_result, baseline_result) in enumerate(
            zip(candidate_run["results"], baseline_run["results"]), start=1
        ):
            # Percentage difference between corresponding individiaul tests 
            # across the same run for both the canddiate and the baseline
            percentage = percentage_difference(
                candidate_result["timings"][0],
                baseline_result["timings"][0],
                f"run {run_number}, test {test_number}",
            )
            run_percentages.append(percentage)
            all_run_results.append(
                {
                    "run": run_number,
                    "test": test_number,
                    "percentage": percentage,
                    "length": candidate_result["length"],
                    "alignment": candidate_result["alignment"],
                    "char": candidate_result["char"],
                }
            )

        if not run_percentages:
            raise ValueError(f"run {run_number} contains no results")

        # Add into the run_summaries the mean of the percentage differences
        # for all 1444 tests for the current run
        run_summaries.append(
            {
                "run": run_number,
                "percentage": fmean(run_percentages),
            }
        )

    # Preserve every result position as a distinct test.  For each position,
    # reduce the five repeated candidate and baseline measurements to medians,
    # then calculate one candidate-versus-baseline percentage.
    result_count = len(candidate_runs[0]["results"])
    test_results = []

    for test_index in range(result_count):
        # Median of timings for all timings at text_index
        # across all 5 runs

        """
        For test 100 it is equivelant to:
            candidate_runs[0]["results"][99]["timings"][0]
            candidate_runs[1]["results"][99]["timings"][0]
            candidate_runs[2]["results"][99]["timings"][0]
            candidate_runs[3]["results"][99]["timings"][0]
            candidate_runs[4]["results"][99]["timings"][0]
        """
        candidate_median = median(
            run["results"][test_index]["timings"][0]
            for run in candidate_runs
        )
        baseline_median = median(
            run["results"][test_index]["timings"][0]
            for run in baseline_runs
        )
        percentage = percentage_difference(
            candidate_median,
            baseline_median,
            f"test {test_index + 1}",
        )
        test_result = candidate_runs[0]["results"][test_index]
        # Results across each run have the same metadata but may differ in the timings
        # so for the meta data, just arbitrarily access at index [0]
        test_results.append(
            {
                "test": test_index + 1,
                "percentage": percentage,
                "length": test_result["length"],
                "alignment": test_result["alignment"],
                "char": test_result["char"],
            }
        )

    if not test_results:
        raise ValueError("benchmark family contains no test results")

    test_percentages = [
        result["percentage"]
        for result in test_results
    ]
    winning_test_count = sum(
        percentage < 0
        for percentage in test_percentages
    )
    # Get 5 individual worst run results
    worst_run_results = sorted(
        all_run_results,
        key=lambda result: result["percentage"],
        reverse=True,
    )[:WORST_RESULT_COUNT]
    # Top 5 worst average test results
    worst_test_results = sorted(
        test_results,
        key=lambda result: result["percentage"],
        reverse=True,
    )[:WORST_RESULT_COUNT]

    return {
        "candidate": candidate_name,
        "baseline": baseline_name,
        "runs": run_summaries,
        "worst_run_results": worst_run_results,
        "family": {
            "test_count": len(test_percentages),
            "test_percentages": test_percentages,
            "average_percentage": fmean(test_percentages),
            "winning_test_count": winning_test_count,
            "winning_tests_percentage": (
                winning_test_count / len(test_percentages) * 100
            ),
            "best_percentage": min(test_percentages),
            "worst_percentage": max(test_percentages),
            "worst_test_results": worst_test_results,
        },
    }


def summarize_run_group(runs, candidate_name, baseline_name):
    """Summarize every benchmark suite for one candidate and baseline."""
    if candidate_name not in runs:
        raise ValueError(
            f"candidate implementation was not loaded: {candidate_name}"
        )
    if baseline_name not in runs:
        raise ValueError(
            f"baseline implementation was not loaded: {baseline_name}"
        )

    candidate_bench_runs = runs[candidate_name]
    baseline_bench_runs = runs[baseline_name]
    candidate_bench_names = set(candidate_bench_runs)
    baseline_bench_names = set(baseline_bench_runs)

    if candidate_bench_names != baseline_bench_names:
        raise ValueError(
            "candidate and baseline contain different benchmark suite runs"
        )

    bench_run_summaries = {}
    worst_test_candidates = []
    worst_run_candidates = []

    for bench_run_name in sorted(candidate_bench_names):
        candidate_individual_runs = candidate_bench_runs[bench_run_name]
        baseline_individual_runs = baseline_bench_runs[bench_run_name]
        candidate_run_names = set(candidate_individual_runs)
        baseline_run_names = set(baseline_individual_runs)

        if candidate_run_names != baseline_run_names:
            raise ValueError(
                f"{bench_run_name}: candidate and baseline contain "
                "different individual runs"
            )

        run_names = sorted(candidate_run_names)
        candidate_runs = [
            candidate_individual_runs[run_name]
            for run_name in run_names
        ]
        baseline_runs = [
            baseline_individual_runs[run_name]
            for run_name in run_names
        ]
        bench_summary = summarize_benchmark_family(
            candidate_runs,
            baseline_runs,
        )
        bench_run_summaries[bench_run_name] = bench_summary

        worst_test_candidates.extend(
            {
                "bench_run": bench_run_name,
                **result,
            }
            for result in bench_summary["family"]["worst_test_results"]
        )
        worst_run_candidates.extend(
            {
                "bench_run": bench_run_name,
                **result,
            }
            for result in bench_summary["worst_run_results"]
        )

    worst_test_results = sorted(
        worst_test_candidates,
        key=lambda result: result["percentage"],
        reverse=True,
    )[:WORST_RESULT_COUNT]
    worst_run_results = sorted(
        worst_run_candidates,
        key=lambda result: result["percentage"],
        reverse=True,
    )[:WORST_RESULT_COUNT]

    return {
        "candidate": candidate_name,
        "baseline": baseline_name,
        "bench_runs": bench_run_summaries,
        "worst_test_results": worst_test_results,
        "worst_run_results": worst_run_results,
    }


def percentage_description(percentage):
    if percentage < 0:
        return "candidate faster"
    if percentage > 0:
        return "candidate slower"
    return "same timing"

def main():
    parser = argparse.ArgumentParser(
        usage=(
            "%(prog)s --candidate=<candidate-name> "
            "--baseline=<baseline-name>"
            "--run-group=<run-group-directory>"
        )
    )
    parser.add_argument(
        "--candidate",
        required=True,
        help="memset implementation to compare against the NEON baseline",
        type=Path,
    )
    parser.add_argument(
        "--baseline",
        required=True,
        help="the baseline which is used to measure against the routine",
        type=Path,
    )
    parser.add_argument(
        "--run-group",
        required=True,
        help="group directory containing the results",
        type=Path,
    )

    arguments = parser.parse_args()
    run_group_directory = arguments.run_group
    baseline = arguments.baseline
    candidate = arguments.candidate

    if not run_group_directory.is_dir():
        raise SystemExit(
            f"Run group directory does not exist: {run_group_directory}"
        )

    """
    There exists two independent dimensions:
                            Run
                    1    2    3    4    5
    Test 1        time time time time time
    Test 2        time time time time time
    Test 3        time time time time time
    ...
    Test 1444     time time time time time

    For each test horizontally, the script reduces each record to its median
    and calculates one percentage for that test.
    """
    load_all_runs(run_group_directory)
    summary = summarize_run_group(
        RUNS,
        candidate.name,
        baseline.name,
    )

    print("Comparison")
    print(f"  Candidate: {summary['candidate']}")
    print(f"  Baseline:  {summary['baseline']}")
    print("  Negative percentages mean the candidate is faster.")
    print("  Positive percentages mean the candidate is slower.")

    for bench_run_name, bench_summary in summary["bench_runs"].items():
        print(f"\nBenchmark suite: {bench_run_name}")
        print("  Individual runs")
        print("    Mean of the per-test differences in each matching run pair.")
        for run_summary in bench_summary["runs"]:
            percentage = run_summary["percentage"]
            print(
                f"    Run {run_summary['run']}: {percentage:+.2f}% "
                f"({percentage_description(percentage)})"
            )

        family = bench_summary["family"]
        average = family["average_percentage"]
        best = family["best_percentage"]
        worst = family["worst_percentage"]
        print("  Overall benchmark family")
        print(
            f"    Each test uses the median timing from {RUN_COUNT} runs; "
            f"{family['test_count']} tests total."
        )
        print(
            f"    Average difference: {average:+.2f}% "
            f"({percentage_description(average)})"
        )
        print(
            f"    Winning tests: {family['winning_test_count']}/"
            f"{family['test_count']} "
            f"({family['winning_tests_percentage']:.2f}%)"
        )
        print(
            f"    Best test: {best:+.2f}% "
            f"({percentage_description(best)})"
        )
        print(
            f"    Worst test: {worst:+.2f}% "
            f"({percentage_description(worst)})"
        )

    worst_test_results = summary["worst_test_results"]
    print(
        f"\nWorst {len(worst_test_results)} tests across all benchmark suites"
    )
    print(
        f"  Ranked by percentage difference using median timings from "
        f"{RUN_COUNT} runs."
    )
    for rank, result in enumerate(worst_test_results, start=1):
        percentage = result["percentage"]
        print(
            f"  {rank}. {result['bench_run']}, test {result['test']}: "
            f"{percentage:+.2f}% "
            f"({percentage_description(percentage)}); "
            f"length={result['length']}, "
            f"alignment={result['alignment']}, char={result['char']}"
        )

    worst_run_results = summary["worst_run_results"]
    print(
        f"\nWorst {len(worst_run_results)} individual results across all "
        "benchmark suites"
    )
    print(
        "  Ranked by percentage difference between matching candidate and "
        "baseline results."
    )
    for rank, result in enumerate(worst_run_results, start=1):
        percentage = result["percentage"]
        print(
            f"  {rank}. {result['bench_run']}, run {result['run']}, "
            f"test {result['test']}: {percentage:+.2f}% "
            f"({percentage_description(percentage)}); "
            f"length={result['length']}, "
            f"alignment={result['alignment']}, char={result['char']}"
        )

if __name__ == "__main__":
    main()
