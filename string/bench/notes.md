## Notes
+ Only to be called on a single implementation, where that implementation has 5 runs inside of a directory
+ Requires there to be a baseline directory, just the generic NEON implementation but specify the name anyway
+ For every result, it is compared against the baseline
+ There is the average of the implementation -- not individual results
+ Percentage of results/runs (will need to make it easily switchable) that were faster than the baseline, and then as a seperate but related metric, the results that were slower
+ 1 function_data dictionary = a single run for a specific implementation

### Five-run structure
```c
candidate_runs = [
    candidate_run_1,
    candidate_run_2,
    candidate_run_3,
    candidate_run_4,
    candidate_run_5,
]

baseline_runs = [
    baseline_run_1,
    baseline_run_2,
    baseline_run_3,
    baseline_run_4,
    baseline_run_5,
]
```