# Purpose:
#   Show how Oracle computes the "start write threshold" 
#   (kcrfa->start_wr_thresh_kcrfa_cln) that sessions check
#   when they allocate redo buffers in a public redo strand. 
# 
#   When the threshold is exceeded, sessions signal lgwr to 
#   start writing.
#
#   The "start write threshold" depends on the number of
#   active public redo strands when lgwr gathers the redo
#   buffers before issuing a redo write. This script also
#   allows changing the number of active public redo strands 
#   to influence the threshold computation.
#
# Author:
#   Christoph Lutz
# 
# Date:
#   Nov-03 2025
#
# Tested on:
#   Oracle 19.26 (RAC) / Exadata 25.1.7
#
# Usage:
#   gdb -q                                         \
#   [-ex 'set $min_actv_strands = <actv_strands>]' \
#   -x kcrfw_redo_gen_ext-poke.gdb                 \
#   -p <pid>
#
#   Example:
#     Read-only mode:
#     gdb -q                                 \
#     -x kcrfw_redo_gen_ext-poke.gdb         \
#     -p 1234 
#
#    Set the nr of active  strands to 16:
#     gdb -q                                 \
#     -ex 'set $min_actv_strands = 16'       \
#     -x kcrfw_redo_gen_ext-poke.gdb         \
#     -p 1234 
#
# Notes:
#   This script is highly experimental, use at your 
#   own risk!
#
# Background information:
#   Before lgwr issues a redo write, it gathers the redo 
#   buffers from the public redo strands and computes a 
#   "start write threshold" for each active strand (in 
#   kcrfw_gather_lwn). In dumps, this threshold appears 
#   as kcrfa->start_wr_thresh_kcrfa_client.
#
#   When a session allocates buffers in a public strand, 
#   it checks the "start write threshold" (kcrfw_redo_gen_ext). 
#   If <= 0 (it can go negative), the session "stalls" to 
#   signal lgwr to flush. The threshold is measured in redo 
#   buffers and decremented for each buffer allocated.
# 
#   The "start write threshold" is computed based on the 
#   write size and the value of parameter _target_log_write
#   _size_percent_for_poke (which defaults to 100). 
#
#   Note that the "start write threshold" also depends on 
#   the number of active public redo strands at gather time 
#   and defaults to:
#
#     single strand active: 
#       wr_thresh = (write_sz * poke_pct/100)
#
#     multiple strands active:: 
#      wr_thresh = (write_sz * poke_pct/100) / actv_strands
#
#   The write size is derived from a per-strand stall size 
#   and computed as:
#
#     write_sz = max_strands * stall_sz
#
#   So, it represents the total write size across all strands.
#
#   Therefore, the "1/3 log buffer full" rule only applies 
#   when the capacity per public strand is <= 1 MB and if all 
#   strands are active at gather time.
#
#   If only one or a few strands are active at gather time, the 
#   computed write_sz can exceed the size of one (or more) active 
#   strands. In that case, a session will never stall to signal 
#   lgwr, unless a strand completely fills up and a "log buffer 
#   space" wait occurs. 
#
#   On Exadata X10+, Pipelined Log Writes make the write_sz 
#   computation even more dynamic. It adapts at runtime, depending 
#   on whether lgwr is running in parallel, how many lg workers 
#   are active and if they are operating in thin or thick mode. 

set pagination off
set confirm off

handle SIGUSR2 nostop noprint

# Addresses and offsets my change in every RU!
set $IN_TRACE             = 0x0
set $IN_KSLGETL           = 0x0
set $IN_KSKTHBWT          = 0x0

set $REDO_BLOCK_SZ        = 0x200

set $OLRW_WRITE_SZ_OFF    = 0x04
set $OLRW_STALL_SZ_OFF    = 0x08
set $OLRW_POKE_PCT_OFF    = 0x10

set $KCRFA_SZ             = 0x130
set $KCRFA_BUFS_AVAIL_OFF = 0x34
set $KCRFA_WR_THRESH_OFF  = 0x38
set $KCRFA_BUFS_TOT_OFF   = 0xf8

set $KSLED_SZ             = 0x38

set $KSLLW_RAL_1          = 3893
set $KSLLW_RAL_2          = 3894
set $KSLLW_RAL_3          = 3896

set $KSBDP_NAME_OFF       = 0x4
set $KSBSDT_STR_OFF       = 0x8


break kcrfw_redo_gen_ext

command 1
    set $IN_TRACE = 1

    # Change the nr of active strands if $min_actv_strand is iset
    if ($min_actv_strands) 
        printf "Changing the number of active strands to: %u\n", $min_actv_strands
        set *(uint32_t *) &kcrf_actv_strands_ = $min_actv_strands
    end

    set $olrw     = (uint64_t) klassvp8_ 
    set $write_sz = *(uint32_t *) ($olrw + $OLRW_WRITE_SZ_OFF)
    set $stall_sz = *(uint32_t *) ($olrw + $OLRW_STALL_SZ_OFF)
    set $poke_pct = *(uint32_t *) ($olrw + $OLRW_POKE_PCT_OFF)

    set $actv_strands = (uint32_t) kcrf_actv_strands_

    if ($actv_strands > 1) 
       set $wr_thresh_calc = ($write_sz * $poke_pct/100 / $actv_strands)
    else
       set $wr_thresh_calc = ($write_sz * $poke_pct/100)
    end

    printf "-> kcrfw_redo_gen_ext: 0x%lx, 0x%lx, 0x%lx\n", $rdi, $rsi, $rdx
    printf "   max_strands = %u\n", (uint32_t ) kcrf_max_strands_
    printf "   actv_strands = %u\n", $actv_strands 
    printf "   wr_thresh_calc = %u\n", $wr_thresh_calc

    continue
end

# kcrfw_redo_gen_ext retprobes
break *kcrfw_redo_gen_ext+4093
break *kcrfw_redo_gen_ext+7452
break *kcrfw_redo_gen_ext+9149
break *kcrfw_redo_gen_ext+14028

commands 2-5
    if ($IN_TRACE) 
        # On return, print kcrfa start and end details
        set $kcrfa_p     = (uint64_t) kcrfsg_
        set $strand_p    = (uint64_t) ($kcrfa_p + ($KCRFA_SZ * $STRAND_NR))
        set $BUFS_TOT2   = *(uint32_t *) ($strand_p + $KCRFA_BUFS_TOT_OFF)
        set $BUFS_AVAIL2 = *(uint32_t *) ($strand_p + $KCRFA_BUFS_AVAIL_OFF)
        set $WR_THRESH2  = *(int32_t *) ($strand_p + $KCRFA_WR_THRESH_OFF)

        printf "%13s%-3u %21s %9s %9s %9s\n", "   strand: #", $STRAND_NR, "", "start", "end", "diff"
        printf "%-38s %9d %9d %9d\n", "      tot_bufs_kcrfa", $BUFS_TOT1, $BUFS_TOT2, ($BUFS_TOT2 - $BUFS_TOT1)
        printf "%-38s %9d %9d %9d\n", "      memory_bufs_available_kcrfa_cln", $BUFS_AVAIL1, $BUFS_AVAIL2, ($BUFS_AVAIL2 - $BUFS_AVAIL1)
        printf "%-38s %9d %9d %9d\n", "      start_wr_thresh_kcrfa_cln", $WR_THRESH1, $WR_THRESH2, ($WR_THRESH2 - $WR_THRESH1)

        #printf "      tot_bufs_kcrfa = %u\n", $bufs_tot
        #printf "      memory_bufs_available_kcrfa_cln = %u\n", $bufs_avail
        #printf "      start_wr_thresh_kcrfa_cln = %d\n", $wr_thresh

        printf "<- kcrfw_redo_gen_ext: %d\n", $eax 
    end

    set $IN_TRACE = 0
    set $LADDR = 0    
    set $STRAND_NR = -1

    set $BUFS_TOT1   = 0
    set $BUFS_TOT2   = 0
    set $BUFS_AVAIL1 = 0
    set $BUFS_AVAIL2 = 0
    set $WR_THRESH1  = 0
    set $WR_THRESH2  = 0

    continue
end

# kcobrh retprobe only
break *kcobrh+320

command 6
    if ($IN_TRACE)
       # Note: not sure if this reflects the redo
       # size correctly. Use it as an indication!
       set $redo_sz = ($eax + (uint32_t) kcrf_kcrrs_sz_ + (uint32_t) kcrf_kcrrs_sz_)
       set $redo_blocks = ($redo_sz / $REDO_BLOCK_SZ)
       printf "<- kcobrh: redo_sz = %u, redo_blocks = %u\n", $redo_sz, $redo_blocks
    end
    continue
end

break kslgetl

command 7
  if ($IN_TRACE && ($rcx == $KSLLW_RAL_1 || $rcx == $KSLLW_RAL_2 || $rcx == $KSLLW_RAL_3))
      set $IN_KSLGETL = 1
      set $LADDR = $rdi
      set $WHY   = $rdx
      printf " -> kslgetl: laddr=%p, wait=%u, why=%u, where=%u\n", $rdi, $rsi, $rdx, $rcx
  end
  continue 
end

# kslgetl retprobe
break *kslgetl+294

command 8
    if ($IN_KSLGETL)
        set $STRAND_NR = $WHY

        if ($eax) 
            # Save kcrfa 'start' details when the RAL acquisition succeeds.
            set $kcrfa_p     = (uint64_t) kcrfsg_
            set $strand_p    = (uint64_t) ($kcrfa_p + ($KCRFA_SZ * $STRAND_NR))
            set $BUFS_TOT1   = *(uint32_t *) ($strand_p + $KCRFA_BUFS_TOT_OFF)
            set $BUFS_AVAIL1 = *(uint32_t *) ($strand_p + $KCRFA_BUFS_AVAIL_OFF)
            set $WR_THRESH1  = *(int32_t *) ($strand_p + $KCRFA_WR_THRESH_OFF)

            printf "    acquired RAL: %p, strand: #%u\n", $LADDR, $STRAND_NR
        else
            printf "failed to acquire RAL: %p\n", $LADDR
        end

        printf " <- kslgetl: %d\n", $eax 

        set $IN_KSLGETL = 0
        set $WHY = 0
    end
    continue
end

break ksbasend

command 9 
    if ($IN_TRACE)
        set $caller_ip = *(uint64_t *) $rsp
        set $tgt_paddr = (uint64_t) $rdi
        set $msg_idx = *(uint32_t *) $rsi
        set $sz = (uint32_t) $rdx
        set $dst_p = ($tgt_paddr + $KSBDP_NAME_OFF)
        set $msg_p = *(uint64_t) (((uint64_t) &ksbsdt) + ($msg_idx * $sz) + $KSBSDT_STR_OFF)

        printf "-> ksbasend: tgt_paddr=%p, msg_idx=%u, sz=%p\n", $rdi, *(uint32_t *) $rsi, $rdx
        printf "   dest = %s [%s]\n", $dst_p, $msg_p
        printf "   caller_ip = %p\n", $caller_ip
    end
    continue
end

break kskthbwt

command 10 
    if ($IN_TRACE)
        set $IN_KSKTHBWT = 1
        set $ev_num = (uint64_t) $rsi
        set $ev_off = ($ev_num * $KSLED_SZ)
        set $wait_str = *(uint64_t *) (((uint64_t) ksledt_) + $ev_off)

        printf "-> kskthbwt: ev#=%u\n", $ev_num
        printf "   start wait: %s\n", $wait_str
    end
    continue
end

break kskthewt

commands 11
    if ($IN_KSKTHBWT)
        set $ev_num = (uint64_t) $rsi
        set $ev_off = ($ev_num * $KSLED_SZ)
        set $wait_str = *(uint64_t *) (((uint64_t) ksledt_) + $ev_off)

        printf "-> kskthewt: ev#=%u\n", $ev_num
        printf "   end wait: %s\n", $wait_str
        set $IN_KSKTHBWT = 0
    end
    continue
end

continue
