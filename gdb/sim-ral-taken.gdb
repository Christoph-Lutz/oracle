# Purpose:
#   Simulate a situation where redo allocation 
#   latch acquisition fails to demonstrate how 
#   Oracle retries latch acquisition and acti-
#   vates new public redo strands.
#
#  Date:
#   Jun-12 2025
#
# Author:
#   Christoph Lutz
#
# Usage:
#   gdb -q -x ./sim-ral-taken.gdb -p <pid>
#
# Tested on:
#   Oracle 19.26, OEL 8.10, gdb 8.2-20.0.2
#
# Notes:
#   This script is unsafe and experimental, as 
#   it alters latch structures without atomic 
#   safeguards. So, if there's concurrent acti-
#   vity and your timing is unfortunate, you 
#   may end up in a mess.
# 
#   Use at your own risk!

set pagination off
set confirm off

# Uncomment these lines if you want to 
# simulate a situation with all public 
# redo strands active:
set *(uint32_t *) &kcrf_actv_strands_ = *(uint32_t *) &kcrf_max_strands_
printf "kcrf_actv_strands = %u\n", (uint32_t) kcrf_actv_strands_

# ptr to redo allocation latch #0 in kcrfsg_
set $RAL0_P=0x600219e0

# redo allocation latch struct size
set $RAL_SZ=0xa0

# tls offset where rand_nr is stored
set $RAND_OFF=0xc1a8

set $laddr=0
set $wait=0
set $strand=0
set $where=0
set $in_ral_get=0
set $in_sim=0
set $attempts=0

# Function entry
break kslgetl

command 1
  set $laddr=$rdi
  set $wait=$rsi
  set $strand=$rdx
  set $where=$rcx
  # printf "-> kslgetl(laddr=%p, wait=0x%lx, strand=%d, where=%d)\n", $laddr, $wait, $strand, $where

  if $laddr == (*(uint64_t *) $RAL0_P) + ($strand * $RAL_SZ) 
    set $in_ral_get=1
    set $rand_nr=*(uint64_t *)($fs_base - $RAND_OFF)
    set $actv_strands=(uint32_t) kcrf_actv_strands_
    printf "-> kslgetl(laddr=%p, wait=0x%lx, strand=%d, where=%d)\n", $laddr, $wait, $strand, $where
    printf "   Active strands: %u\n", $actv_strands
    printf "   Strand calculation: rand_nr %% kcrf_actv_strands_ = %lu %% %u = %u\n", $rand_nr, $actv_strands, ($rand_nr % $actv_strands)

    if $attempts < 2
      printf "   Simulating latch held situation\n"
      set $in_sim=1
      set *(uint64_t *) $laddr=0x12345
    end

    set $attempts++
  end

  continue
end

# Function return
break *kslgetl+294

command 2
  if $in_ral_get == 1
    printf "<- kslgetl: 0x%lx\n", $eax
    # printf "   Active strands: %d\n", (uint32_t) kcrf_actv_strands_
    set $in_ral_get=0
  end

  if $in_sim == 1
    printf "   Clearing latch held simulation\n"
    set *(uint64_t *) $laddr=0x0
    set $in_sim=0
  end

  if $attempts > 2
    printf "   Done, exiting ...\n\n"
    quit
  end

  continue
end

continue
