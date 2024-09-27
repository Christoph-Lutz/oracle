/*
 * Program:
 *  chkval.c
 *
 * Date:
 *  Unknown (probably around 2010/11).
 *  (can't remember where the idea and approach
 *  came from and if any inputs on that matter, 
 *  let me know so that I can give proper credits)
 *
 * Author:
 *  Christoph Lutz
 *
 * Purpose:
 *   This program computes the KCBH chkval.
 *
 * Notes:
 *  The program uses a default block size of 8k.
 *  Use this program at your own risk!
 *
 * Compilation:
 *  gcc -o chkval chkval.c
 *
 * Usage:
 *  ./chkval <datafile> <block_no>
 */

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#define BLOCKSIZE 8192
#define CHKVALOFF 16

/* compute oracle block checksum (chkval in block dumps)    */
/* and read chkval currently stored in block                */
/* the checksum algorithm is the XOR of all 2-byte pairs    */
/* in the block except the chkval itself                    */ 
int comp_chkval(int block_size, unsigned char *buffer, int *storedval) {

	unsigned char curpair[2]="";   /* current 2 byte pair in block     */
	unsigned char prevpair[2]="";  /* previous 2 byte pair in block    */
	unsigned char res[2]="";       /* result of (prevpair XOR curpair) */
	int count=0;
	int chkval=0;

	while(count<block_size) {

		/* read stored chkval and then */
		/* skip byte pair at CHKVALOFF */
		/* to exlude it from XOR       */
		/* computation                 */
		if(count == CHKVALOFF) {
			memmove(storedval, &buffer[count], 2);
			count=count+2;
		}
		else {
			memmove(curpair, &buffer[count], 2);
			xor_pairs(prevpair, curpair, res);	
			memmove(prevpair, res, 2);
			count=count+2;
		}
	}

	/* copy 2-byte XOR result  */
	/* to int value and return */
	memmove(&chkval, &res[0], 2);
	return chkval;
}

int xor_pairs(unsigned char *pair1, unsigned char *pair2, unsigned char *out) {

        int c=0;
        while(c<2) {
                out[c]=pair1[c]^pair2[c];
                c++;
        }
        return 0;
}

 
int main(int argc, char **argv) {

	int fp;
    	unsigned char buffer[BLOCKSIZE];
	char filename[]="";
	int blockno=0;
	int nbytes=0;
	int chkval=0;
	int storedval=0;

	if(argc!=3) {
		printf("usage: %s <datafile path> <blockno>\n", argv[0]);
		exit(EXIT_FAILURE);
	}
	else {
		strncpy(filename, argv[1], strlen(argv[1]));
		blockno=atoi(argv[2]);
	}

	if((fp=open(filename, O_RDONLY))<0) {
		perror("open() error");
		exit(EXIT_FAILURE);
	}

	if((nbytes=pread(fp, buffer, BLOCKSIZE, BLOCKSIZE*blockno))<=0) {
		perror("pread() error");
		exit(EXIT_FAILURE);
	} 
	else {
		printf("bytes read: %d\n", nbytes);
	}

	chkval=comp_chkval(BLOCKSIZE, buffer, &storedval);
	printf("computed chkval: %02x\n", chkval);
	printf("stored chkval: %02x\n", storedval);

	if(chkval != storedval) {
		printf("computation differs!\n");
	}

  	close(fp);
  	return 0;
}
