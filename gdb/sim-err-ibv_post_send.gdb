# Purpose:
#   Simulate ibv_post_send errors. Written to simulate lgwr
#   pmemlog rdma write failures on Exadata.
#
# Author: 
#   Christoph Lutz
#
# Date:
#   2024-06-15
#
# Usage:
#   gdb -q -x sim-err-ibv_post_send.gdb <lgwr_pid>
#
# Notes:
#   The script uses various ibv structs and enums. You 
#   must therefore create a symbol file first:
#
#     Step 1: Create the file ibv_syms.c
#
#     #include <stdio.h>
#     #include <infiniband/verbs.h>
#
#     struct ibv_wc wc;
#     struct ibv_send_wr wr;
#     struct ibv_sge sge;
#
#     enum ibv_wr_opcode wr_opcode;
#     enum ibv_wc_status wc_status;
#     enum ibv_wc_opcode wc_opcode;
#
#     Step 2: Compile the symbol file
#
#     gcc -c -g ibv_syms.c -o /tmp/ibv_syms.o
#
#   Idea is the following:
#   Log the work request id (wr_id) for a given work request
#   operation (opcode) and then when the completion queue (cq)
#   is polled for completion, overwrite the return value with
#   an error code.
#
#   If multiple lgwr processes are active, you may need to run
#   the script against a LGnn process (or all of them).
#
#   Check the LGWER (or LGnn) trace file(s) after the script 
#   completes.
#
#   This script is experimental and dangerouse, use it at your 
#   own risk!

set pagination off
set confirm off
add-symbol-file /tmp/ibv_syms.o 0

handle SIGSEGV nostop noprint
handle SIGUSR2 nostop noprint

set $opcode = IBV_WR_SEND
# set $error = IBV_WC_RNR_RETRY_EXC_ERR 
set $error = IBV_WC_RETRY_EXC_ERR 
set $wc = 0
set $wr_id = 0

break ibv_post_send
command 1
  if $wr_id == 0 && (*(struct ibv_send_wr *) $rsi)->opcode == $opcode
    set $wr_id = (*(struct ibv_send_wr *) $rsi)->wr_id
    printf "wr_id=%lu\n", $wr_id
  end
  cont
end

break ibv_poll_cq
command 2
  set $wc = (struct ibv_wc *) $rdx
  printf "wc=%p\n", $wc
  cont
end

# Return offset may change between
# different versions of libmlx
break *mlx5_poll_cq_v1+634
command 3
  if ((struct ibv_wc *) $wc)->wr_id == $wr_id
    printf "Injecting error %d into wr: %lu\n", $error, ((struct ibv_wc *) $wc)->wr_id
    set {int} &((struct ibv_wc *) $wc)->status = $error
    quit
  end
  if ((struct ibv_wc *) $wc)->wr_id != $wr_id
    cont
  end
end

continue
