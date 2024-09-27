#!/usr/bin/bash
# set -x
# Purpose: 
#   Calculate the physical Exadata cell disk offset based on
#   the given grid disk and asm offset.
#
# Author:
#   Christoph Lutz
#
# Date:
#   May-02 2024
#
# Usage:
#   celldisk_off_calc.sh <grid_disk> <asm_offset> [<block_size>]
#
# Parameters:
#   grid_disk : grid disk name
#   asm_offset: asm offset (in blocks, as returned by 'asmcmd mapblk') 
#   block_size: db or acfs block size (optional, defaults to 8k)
#
# Tested on:
#   Exadata System Software 23.1.7.0.0.231109
#   ASM 19.21
#   Oracle 19.22
#
# Notes:
#   This script is mainly a wrapper around the undocumented
#   cellutil utility and parses its output. That means, it
#   relies on the cellutil output and output ordering (which
#   is very brittle). So, if the cellutil output changes in
#   a future version, the script may break. Also, this script
#   is potentially dangerous - USE IT AT YOUR OWN RISK!
#
#   If you use the script with acfs, the asm_offset is the
#   value calculated by: doffset / length
#   Both, 'doffset' and 'length' are provided by the command
#   'acfsutil info file -du ...'

DEFAULT_BLOCK_SIZE=8192

[[ "$#" -lt "2" ]] && echo && echo "Usage: $0 <grid_disk> <asm_offset> [<block_size>]" && echo && exit 1

BLOCK_SIZE="${3:-$DEFAULT_BLOCK_SIZE}"

GRID_DISK="$1"
CELL_DISK="$(echo $GRID_DISK | sed -n -e 's/^.*\(CD_\)/\1/p')"
ASM_OFFSET="$2"

echo
echo "INFO: Calculating disk block offset ..."
echo "INFO: grid disk: $GRID_DISK"
echo "INFO: asm offset: $ASM_OFFSET"
echo "INFO: cell disk: $CELL_DISK"
echo "INFO: block size: $BLOCK_SIZE"

DISK=$(cellcli -e "list celldisk $CELL_DISK detail" | grep devicePartition | awk '{print $2}')
echo "INFO: cell disk partition: $DISK"

SECTOR_SIZE=$(cellutil -d $DISK -c primary -s header | grep sectorSize | awk '{print $2}')
echo "INFO: cell disk sector size (bytes): $SECTOR_SIZE"

EXTENT_SIZE=$(cellutil -d $DISK -c primary -s info | grep gdiskExtentSize | awk '{print $2}')
echo "INFO: grid disk extent size (sectors): $EXTENT_SIZE"

gdiskName="$(echo $GRID_DISK | sed -e 's/./& /g')"
echo "INFO: gdiskName: $gdiskName"

gdiskId=$(cellutil -d $DISK -c primary -s gdtable | grep -i -B15 "$gdiskName" | grep gdiskId | awk '{print $2}')
echo "INFO: gdiskId: $gdiskId"

gdiskSegments=$(cellutil -d $DISK -c primary -s gdtable | grep -B16 "$gdiskName" | grep gdiskSegments | awk '{print $2}')
echo "INFO: gdiskSegments: $gdiskSegments"

SegmentMapRecords=( $(cellutil -d $DISK -c primary -s segmap | grep --no-group-separator -B1 -A3 "gdiskId: $gdiskId" | grep SegmentMapRecord | awk '{print $2 " "}' | sed -e 's/://g' | tr -d '\n') )
numSegmentMapRecords="${#SegmentMapRecords[@]}"
echo "INFO: SegmentMapRecords: $numSegmentMapRecords"

declare -A startExtents
declare -A segmentSizes

for ((i=0; i<numSegmentMapRecords; i++))
 do
    record="${SegmentMapRecords[$i]}"
    echo "INFO: SegmentMapRecord #${record}:"

    startExtent=$(cellutil -d $DISK -c primary -s segmap | grep --no-group-separator -B1 -A3 "gdiskId: $gdiskId" | grep --no-group-separator -A2 "SegmentMapRecord $record:" | grep startExtent | awk '{print $2}')
    echo "INFO:   startExtent: $startExtent"

    startExtents[$i]=$((startExtent * EXTENT_SIZE * SECTOR_SIZE))
    echo "INFO:   startExtent (bytes): ${startExtents[$i]}"

    segmentSize=$(cellutil -d $DISK -c primary -s segmap | grep --no-group-separator -B1 -A3 "gdiskId: $gdiskId" | grep --no-group-separator -A3 "SegmentMapRecord $record:" | grep segmentSize | awk '{print $2}')
    echo "INFO:   segmentSize (extents): $segmentSize"

    segmentSizes[$i]=$((segmentSize * EXTENT_SIZE * SECTOR_SIZE))
    echo "INFO:   segmentSize (bytes): ${segmentSizes[$i]}"
done

echo "INFO: asm offset (blocks): $ASM_OFFSET"
ASM_OFFSET_BYTES="$((ASM_OFFSET * BLOCK_SIZE))"
echo "INFO: asm offset (bytes): $ASM_OFFSET_BYTES"

for ((i=0; i<numSegmentMapRecords; i++))
 do
    if [[ "$ASM_OFFSET_BYTES" -gt "${segmentSizes[$i]}" ]]
     then
        continue
     else
        TARGET_GD_SEG_IDX="$i"
        echo "INFO: target gd segment#: ${SegmentMapRecords[$TARGET_GD_SEG_IDX]}"
        break
    fi
done

for ((i=0; i<TARGET_GD_SEG_IDX; i++))
 do
   GD_SEG_OFFSET="$((GD_SEG_OFFSET + segmentSizes[$i]))"
done

echo "INFO: sum of grid disk segments offset: $GD_SEG_OFFSET"

TARGET_GD_START_EXTENT="${startExtents[$TARGET_GD_SEG_IDX]}"
echo "INFO: target grid disk startExtent (bytes): $TARGET_GD_START_EXTENT"

DISK_BLOCK_OFF_BYTES="$((TARGET_GD_START_EXTENT + (ASM_OFFSET_BYTES - GD_SEG_OFFSET)))"
echo "INFO: grid disk block offset (bytes): $DISK_BLOCK_OFF_BYTES"

DISK_BLOCK_OFF="$((DISK_BLOCK_OFF_BYTES / BLOCK_SIZE))"
echo "INFO: grid disk block offset (blocks): $DISK_BLOCK_OFF"

echo
echo "Run the following command to extract the block:"
echo "dd if=$DISK of=${DISK_BLOCK_OFF}.dmp bs=$BLOCK_SIZE count=1 skip=$DISK_BLOCK_OFF"

echo
echo "Run the following command to restore the block - DANGEROUS!"
echo "dd if=${DISK_BLOCK_OFF}.dmp of=$DISK bs=$BLOCK_SIZE count=1 seek=$DISK_BLOCK_OFF conv=notrunc"

echo

exit 0
