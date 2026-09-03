#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
from shutil import get_terminal_size
from statistics import fmean, median

"""
    + bench-memset-random are all randomly sized and aligned zero-fill memset operations
    + the random results have the average timing and length for all memset calls
    + 
"""

BENCHMARK = "bench-memset"
RUN_COUNT = 5
WORST_RESULT_COUNT = 5

# TOD: Add flag to specify the benchmark family and then handle that appropriately

def load_run(path):
    """
    Return a runs meta-data and results from the glibc benchmark
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


def load_all_runs(run_directory):
    """Load all runs for a benchmark family"""
    runs = []

    for run_number in range(1, RUN_COUNT + 1):
        filename = f"{BENCHMARK}.run-{run_number}.out"
        path = run_directory / filename
        runs.append(load_run(path))

    validate_run_series(run_directory.name, runs)
    return runs


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


def percentage_description(percentage):
    if percentage < 0:
        return "candidate faster"
    if percentage > 0:
        return "candidate slower"
    return "same timing"


def graph_range(percentages):
    lower = min(0, min(percentages))
    upper = max(0, max(percentages))

    if lower == upper:
        padding = max(abs(lower) * 0.05, 1.0)
    else:
        padding = (upper - lower) * 0.05

    return lower - padding, upper + padding


def print_terminal_graph(summary):
    """Print a compact scatter graph that fits the current terminal."""
    percentages = summary["family"]["test_percentages"]
    average = summary["family"]["average_percentage"]
    lower, upper = graph_range(percentages)
    plot_height = 20
    terminal_width = get_terminal_size(fallback=(100, 24)).columns
    plot_width = max(20, min(100, terminal_width - 24))
    grid = [[" " for _ in range(plot_width)] for _ in range(plot_height)]

    def row_for(percentage):
        return round(
            (upper - percentage)
            / (upper - lower)
            * (plot_height - 1)
        )

    zero_row = row_for(0)
    average_row = row_for(average)

    for column in range(plot_width):
        grid[zero_row][column] = "-"
        grid[average_row][column] = "="

    test_denominator = max(len(percentages) - 1, 1)
    for test_index, percentage in enumerate(percentages):
        column = round(test_index / test_denominator * (plot_width - 1))
        grid[row_for(percentage)][column] = "*"

    labelled_rows = {
        0,
        plot_height // 4,
        plot_height // 2,
        plot_height * 3 // 4,
        plot_height - 1,
        zero_row,
        average_row,
    }

    print("\nTerminal graph")
    print("  Median-based percentage difference for each test.")
    for row_number, row in enumerate(grid):
        if row_number == zero_row:
            label = "+0.0%"
        elif row_number == average_row:
            label = f"{average:+.1f}%"
        elif row_number in labelled_rows:
            percentage = (
                upper
                - row_number / (plot_height - 1) * (upper - lower)
            )
            label = f"{percentage:+.1f}%"
        else:
            label = ""

        annotation = ""
        if row_number == average_row:
            annotation = " average"
        if row_number == zero_row:
            annotation += " baseline"

        print(f"{label:>10} |{''.join(row)}|{annotation}")

    axis_padding = max(plot_width - len(str(len(percentages))) - 1, 1)
    print(f"{'':>10} +{'-' * plot_width}+")
    print(
        f"{'Test':>10}  1{' ' * axis_padding}{len(percentages)}"
    )
    print("  * = one or more tests; - = baseline; = = overall average")


def main():
    parser = argparse.ArgumentParser(
        usage=(
            "%(prog)s --routine=<routine-directory> "
            "--baseline=<baseline-directory> [--graph]"
            "--family=<memset-benchmark-family>"
        )
    )
    parser.add_argument(
        "--routine",
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
        "--graph",
        action="store_true",
        help="print a graph directly in the terminal",
    )
    # parser.add_argument(
    #     "--family",
    #     required=True,
    #     help="memset benchmark family",
    #     type=Path,
    # )
    arguments = parser.parse_args()
    baseline_directory = arguments.baseline
    candidate_directory = arguments.routine
    # benchmark_family = arguments.family

    if not baseline_directory.is_dir():
        raise SystemExit(
            f"baseline directory does not exist: {baseline_directory}"
        )

    if not candidate_directory.is_dir():
        raise SystemExit(
            f"candidate directory does not exist: {candidate_directory}"
        )

    # if not benchmark_family.is_dir():
    #     raise SystemExit(
    #         f"benchmark family directory does not exist: {benchmark_family}"
    #     )

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
    # List of the 5 candidate runs, where each index will then contain the 1444 results
    candidate_runs = load_all_runs(candidate_directory)
    baseline_runs = load_all_runs(baseline_directory)
    summary = summarize_benchmark_family(candidate_runs, baseline_runs)

    print("Comparison")
    print(f"  Candidate: {summary['candidate']}")
    print(f"  Baseline:  {summary['baseline']}")
    print("  Negative percentages mean the candidate is faster.")
    print("  Positive percentages mean the candidate is slower.")

    print("\nIndividual runs")
    print("  Mean of the per-test differences in each matching run pair.")
    for run_summary in summary["runs"]:
        percentage = run_summary["percentage"]
        print(
            f"  Run {run_summary['run']}: {percentage:+.2f}% "
            f"({percentage_description(percentage)})"
        )

    family = summary["family"]
    average = family["average_percentage"]
    best = family["best_percentage"]
    worst = family["worst_percentage"]
    print("\nOverall benchmark family")
    print(
        f"  Each test uses the median timing from {RUN_COUNT} runs; "
        f"{family['test_count']} tests total."
    )
    print(
        f"  Average difference: {average:+.2f}% "
        f"({percentage_description(average)})"
    )
    print(
        f"  Winning tests: {family['winning_test_count']}/"
        f"{family['test_count']} "
        f"({family['winning_tests_percentage']:.2f}%)"
    )
    print(
        f"  Best test: {best:+.2f}% "
        f"({percentage_description(best)})"
    )
    print(
        f"  Worst test: {worst:+.2f}% "
        f"({percentage_description(worst)})"
    )

    worst_test_results = family["worst_test_results"]
    print(f"\nWorst {len(worst_test_results)} tests across all runs")
    print(
        f"  Ranked by percentage difference using median timings from "
        f"{RUN_COUNT} runs."
    )
    for rank, result in enumerate(worst_test_results, start=1):
        percentage = result["percentage"]
        print(
            f"  {rank}. Test {result['test']}: {percentage:+.2f}% "
            f"({percentage_description(percentage)}); "
            f"length={result['length']}, "
            f"alignment={result['alignment']}, char={result['char']}"
        )

    worst_run_results = summary["worst_run_results"]
    print(f"\nWorst {len(worst_run_results)} individual results across all runs")
    print(
        "  Ranked by percentage difference between matching candidate and "
        "baseline results."
    )
    for rank, result in enumerate(worst_run_results, start=1):
        percentage = result["percentage"]
        print(
            f"  {rank}. Run {result['run']}, test {result['test']}: "
            f"{percentage:+.2f}% "
            f"({percentage_description(percentage)}); "
            f"length={result['length']}, "
            f"alignment={result['alignment']}, char={result['char']}"
        )

    if arguments.graph:
        print_terminal_graph(summary)


if __name__ == "__main__":
    main()
