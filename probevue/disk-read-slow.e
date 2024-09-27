#!/bin/probevue
/* 
 * Purpose:
 *   Trace disk read requests slower than the given threshold.
 * 
 * Author:
 *   Christoph Lutz
 * 
 * Date:
 *  Unknown
 */

__global int REQUEST_SIZE;
__global int THRESHOLD_MS;

@@BEGIN
{
    REQUEST_SIZE = $1;
    THRESHOLD_MS = $2;
    printf("Tracing slow read I/O requests (request_size: %d, threshold_ms: %d) ... hit ^C to stop\n", REQUEST_SIZE, THRESHOLD_MS);
}

@@io:disk:iostart:read:*
when(__iobuf->bcount == REQUEST_SIZE)
{
    ts_entry[__iobuf->bufid] = (long long) timestamp();
}

@@io:disk:iodone:read:*
when(ts_entry[__iobuf->bufid])
{
    __auto ts_exit;
    __auto delta_us;
    __auto delta_ms;

    ts_exit = (long long) timestamp();
    delta_us = (long long) diff_time(ts_entry[__iobuf->bufid], ts_exit, MICROSECONDS);
    delta_ms = delta_us / 1000;

    if(delta_ms > THRESHOLD_MS) {
        disk_name = __diskinfo->name;
        path_id = __iopath->path_id;
        cmd_type = __diskcmd->cmd_type;
        retry_count = __diskcmd->retry_count;
        path_switch_count = __diskcmd->path_switch_count;
        status_validity = __diskcmd->status_validity;
        scsi_status = __diskcmd->scsi_status;
        adapter_status = __diskcmd->adapter_status;

        printf("%A: %s path=%d retries=%d path_switches=%d status=0x%x scsi_status=0x%x adapter_status=0x%x\n", (probev_timestamp_t) ts_exit, disk_name, path_id, retry_count-1, path_switch_count, status_validity, scsi_status, adapter_status);
    }

    delete(ts_entry, __iobuf->bufid);
}

