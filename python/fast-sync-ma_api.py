#!/usr/bin/python
# Purpose:
#   Illustrate how ckpt calculates the adaptive
#   sleep time used in Fast Log File Sync every
#   3 sec (in kcrfw_alfs_cron_job).
#
#   At runtime, the input values for calculating 
#   the Fast Sync sleep time are collected by the
#   fg processes on commit or rollback (kcrf_commit_
#   force_int) and by lgwr and the lg worker proc-
#   esses (kcrfw_alfs_save_redowrite_time).
# 
#   The script's output is similar to what ckpt 
#   logs to trace with event 10468 set at level 8:
# 
#     SQL> oradebug setorapname ckpt
#     SQL> oradebug event 10468 trace name context forever, level 8
#     SQL> oradebug event 10468 trace name context off
#
# Date:
#   Jul-13 2025
#
# Author:
#   Chrisotph Lutz
#
# Usage:
#   ./fast-sync-ma_api <params.json>
#
# Example:
#   1. Save the following values to a json file:
#      {
#          "sleep_target_pct_prm": 50,
#          "prev_sleep_cnt": 3235,
#          "sleep_cnt": 3435,
#          "prev_usleep_cnt": 3009,
#          "usleep_cnt": 3202,
#          "prev_sleep_oh": 28774,
#          "sleep_oh": 30910
#          "min_redo_write": 26,
#          "redo_write": 78731,
#          "ma_per_sleep_oh": 5472,
#          "ma_api": 71911
#      }
#
#   2. Run the script:
#      ./fast-sync-ma_api params.json
#
#   3. For real-life inputs, you can collect all 
#      required input parameters at runtime with 
#      the following bpftrace script (the script 
#      will create a json params file):
# 
#      ./kcrfw_alfs_cron_job.bt-fast-sync-sleep-inputs.bt <ckpt_pid> 
#
# Input parameter description:
#   The Fast Sync adaptive sleep time calculation
#   requires the following inputs:
#
#   - sleep_target_pct_prm: 
#     Value of parameter _fg_fast_sync_sleep_target_pct.
#
#   - prev_sleep_cnt: 
#     Total number of Fast Sync sleeps from the previous
#     measurement.
#
#   - sleep_cnt:
#     Current number of Fast Sync sleeps.
#
#   - prev_usleep_cnt:
#     Total number of Fast Sync usleeps from the previous
#     measurement (a usleep is logged when a fg finds its
#     sync scn on disk after sleep; that is, a fg doesn't
#     need to spin and backoff).
#
#   - usleep_cnt
#     Current number of Fast Sync usleeps.
#     
#   - prev_sleep_oh:
#     Total sleep overhead time from the previous measure-
#     ment (sleep overhead is calculated as
#   
#   - sleep_oh:
#     Average sleep overhead time per Fast Sync sleep
#     (sleep overhead is the difference between the Fast
#     Sync elapsed time and the target sleep time).
#
#   - ma_per_sleep_oh:
#     Exponentially smoothed average of the sleep overhead
#     (ma probably means "Moving Average").
#
#   - ma_api:
#     Adaptive sleep duration used by Fast Sync. The value 
#     adjusts gradually in response to the difference between 
#     actual sleep behavior (usleep_pct) and the target sleep 
#     percentage (sleep_target_pct_prm), and it's smoothed 
#     over time (α = 2/17 ≈ 0.118) to avoid oscillations.
#
# Tested on:
#   Oracle 19.26 / Exadata 24.1.2

import json
import sys

def update_ma_api(
    sleep_target_pct_prm,
    prev_sleep_cnt,
    sleep_cnt,
    prev_usleep_cnt,
    usleep_cnt,
    prev_sleep_oh,
    sleep_oh,
    min_redo_write,
    redo_write,
    ma_per_sleep_oh,
    ma_api):

    print("\n---- Fast Sync Adaptive Sleep Input Parameters ----")
    print(f"sleep_target_pct_prm = {sleep_target_pct_prm}")
    print(f"prev_sleep_cnt       = {prev_sleep_cnt}")
    print(f"sleep_cnt            = {sleep_cnt}")
    print(f"prev_usleep_cnt      = {prev_usleep_cnt}")
    print(f"usleep_cnt           = {usleep_cnt}")
    print(f"prev_sleep_oh        = {prev_sleep_oh}")
    print(f"sleep_oh             = {sleep_oh}")
    print(f"min_redo_write       = {min_redo_write}")
    print(f"redo_write           = {redo_write}")
    print(f"ma_per_sleep_oh      = {ma_per_sleep_oh}")
    print(f"ma_api               = {ma_api}\n")

    # Precondition checks
    if sleep_cnt < prev_sleep_cnt + 100:
        print("Skip: not enough new sleep samples.")
        sys.exit(1)
    
    if min_redo_write == 0 or redo_write == 0:
        print("Skip: redo write thresholds invalid.")
        sys.exit(1)

    if usleep_cnt < prev_usleep_cnt:
        print("Skip: usleep counter regressed.")
        sys.exit(1)

    # Sleep count and pct
    delta_sleep_cnt = sleep_cnt - prev_sleep_cnt
    usleep_delta = usleep_cnt - prev_usleep_cnt
    usleep_pct = (usleep_delta * 100) // delta_sleep_cnt

    # Delta adj
    diff = usleep_pct - sleep_target_pct_prm

    if diff > 0:
        if diff > 20:
            delta_adj = 10
        elif diff > 15:
            delta_adj = 7
        elif diff > 10:
            delta_adj = 5
        elif diff > 5:
            delta_adj = 3
        elif diff > 2:
            delta_adj = 2
        else:
            delta_adj = 1
    elif diff < 0:
        if diff > -2:
            delta_adj = -1
        elif diff > -5:
            delta_adj = -2
        elif diff > -10:
            delta_adj = -3
        elif diff > -15:
            delta_adj = -5
        elif diff > -20:
            delta_adj = -7
        else:
            delta_adj = -10
    else:
        delta_adj = 0

    # Calculate prop api
    prop_api = (ma_api // 1000) + delta_adj
    if prop_api <= 0:
        prop_api = 1

    # Per sleep overhead
    # ma_per_sleep_oh is an exponentially smoothed average
    per_sleep_oh = (sleep_oh - prev_sleep_oh) // delta_sleep_cnt
    ma_per_sleep_oh = ma_per_sleep_oh + ((per_sleep_oh * 1000 - ma_per_sleep_oh) * 2) // 17
    ma_per_sleep_oh = ma_per_sleep_oh // 1000

    # Min/max bounds
    if min_redo_write <= ma_per_sleep_oh:
        min = 1
    else:
        min = min_redo_write - ma_per_sleep_oh

    if (redo_write * 2) <= ma_per_sleep_oh:
        max = 1
    else:
        max = (redo_write * 2) - ma_per_sleep_oh

    # Clamp prop api
    if prop_api < min:
        new_api = min
        adj_type = "min"
    elif prop_api > max:
        new_api = max
        adj_type = "max"
    else:
        new_api = prop_api
        adj_type = "avg"

    # Calculate new ma_api / fast sync sleep time
    api_delta = (new_api * 1000) - ma_api
    ma_api = ma_api + (api_delta * 2) // 17

    print("---- Fast Sync Adaptive Sleep Update Summary   ----")
    print(f"delta sleep cnt      = {sleep_cnt - prev_sleep_cnt}")
    print(f"prev u/sleep cnt     = {prev_usleep_cnt}")
    print(f"u/sleep cnt          = {usleep_cnt}")
    print(f"u/sleep%             = {usleep_pct}")
    print(f"delta adj            = {delta_adj}")
    print(f"prev sleep oh        = {prev_sleep_oh}")
    print(f"sleep oh             = {sleep_oh}")
    print(f"per sleep o/h        = {per_sleep_oh}")
    print(f"ma per sleep o/h     = {ma_per_sleep_oh}")
    print(f"redo write           = {redo_write}")
    print(f"min                  = {min}")
    print(f"max                  = {max}")
    print(f"adj type             = {adj_type}")
    print(f"prop. api            = {prop_api}")
    print(f"new api              = {new_api}")
    print(f"ma_api               = {ma_api}")
    print(f"ma_api (scaled)      = {ma_api // 1000}\n")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: ma_api.py <params.json>")
        sys.exit(1)

    param_file = sys.argv[1]

    try:
        with open(param_file, "r") as f:
            param_dict = json.load(f)
    except Exception as e:
        print(f"Error reading parameter file: {e}")
        sys.exit(1)

    update_ma_api(**param_dict)
