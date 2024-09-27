#!/bin/probevue
/*
 * Purpose:
 *   Trace read requests accross the aix io stack and show 
 *   the request and queue latency at each layer if a request
 *   takes longer than the given threshold.
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
    printf("Tracing slow I/O requests (request_size: %d, threshold_ms: %d) ... hit ^C to stop\n", REQUEST_SIZE, THRESHOLD_MS);
}

@@io:lvm:entry:read:*
when (__iobuf->bcount == REQUEST_SIZE)
{
    lvm_entry[__iobuf->bufid] = (long long) timestamp();
}

@@io:lvm:iostart:read:*
when (lvm_entry[__iobuf->bufid])
{
    lvm_start[__iobuf->bufid] = (long long) timestamp();
    lvm_child_buf[__iobuf->child_bufid] = __iobuf->child_bufid;
}

@@io:disk:entry:read:*
when (__iobuf->bufid == lvm_child_buf[__iobuf->bufid])
{
    disk_entry[__iobuf->bufid] = (long long) timestamp();
    delete(lvm_child_buf, __iobuf->bufid);
}

@@io:disk:iostart:read:*
when (disk_entry[__iobuf->bufid])
{
    disk_start[__iobuf->bufid] = (long long) timestamp();
}

@@io:disk:iodone:read:*
when (disk_start[__iobuf->bufid])
{
   disk_req[__iobuf->bufid] = (long long) diff_time(disk_start[__iobuf->bufid], timestamp(), MICROSECONDS);
   delete(disk_start, __iobuf->bufid);
}

@@io:disk:exit:read:*
when (disk_entry[__iobuf->bufid])
{
    disk_tot[__iobuf->bufid] = (long long) diff_time(disk_entry[__iobuf->bufid], timestamp(), MICROSECONDS);
    delete(disk_entry, __iobuf->bufid);
}

@@io:lvm:iodone:read:*
when (lvm_start[__iobuf->bufid])
{
    disk_lat[__iobuf->bufid] = disk_tot[__iobuf->child_bufid];
    disk_queue[__iobuf->bufid] =  disk_tot[__iobuf->child_bufid] - disk_req[__iobuf->child_bufid];
    lvm_req[__iobuf->bufid] = (long long) diff_time(lvm_start[__iobuf->bufid], timestamp(), MICROSECONDS);

    delete(disk_req, __iobuf->child_bufid);
    delete(disk_tot, __iobuf->child_bufid);
    delete(lvm_start, __iobuf->bufid);
}

@@io:lvm:exit:read:*
when (lvm_entry[__iobuf->bufid])
{
    __auto lvm_tot;
    __auto lvm_queue;
    __auto lvm_disk_lat;
    __auto lvm_disk_queue;

   lvm_tot = diff_time(lvm_entry[__iobuf->bufid], timestamp(), MICROSECONDS);

    if ( (lvm_tot) > THRESHOLD_MS) {
        lvm_queue = lvm_tot - lvm_req[__iobuf->bufid];
        lvm_disk_lat = disk_lat[__iobuf->bufid];
        lvm_disk_queue = disk_queue[__iobuf->bufid];

        printf("%A: %s lvm=%lld us lvm_q=%lld us disk=%lld us disk_q=%lld us\n",
               timestamp(),
               __lvol->name,
               lvm_tot,
               lvm_queue,
               lvm_disk_lat,
               lvm_disk_queue);
    }

    delete(disk_lat, __iobuf->bufid);
    delete(disk_queue, __iobuf->bufid);
    delete(lvm_req, __iobuf->bufid);
    delete(lvm_entry, __iobuf->bufid);
}
