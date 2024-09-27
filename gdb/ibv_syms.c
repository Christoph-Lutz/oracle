/* 
 * Symbol file for use with gdb, compile with:
 * gcc -c -g ibv_syms.c -o /tmp/ibv_syms.o
 */
#include <stdio.h>
#include <infiniband/verbs.h>

struct ibv_wc wc;
struct ibv_send_wr wr;
struct ibv_sge sge;

enum ibv_wr_opcode wr_opcode;
enum ibv_wc_status wc_status;
enum ibv_wc_opcode wc_opcode;
