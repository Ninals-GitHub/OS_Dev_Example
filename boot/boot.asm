[BITS 16]
ORG	0
;***********************************************
; BIOS parameter blocks(FAT12)
;***********************************************

JMP	BOOT		;BS_jmpBoot
BS_jmpBoot2		DB	0x90
BS_OEMName		DB	"MyOS    "
BPB_BytsPerSec	DW	0x0200			;BytesPerSector
BPB_SecPerClus	DB	0x01			;SectorPerCluster
BPB_RsvdSecCnt	DW	0x0001			;ReservedSectors
BPB_NumFATs	DB	0x02				;TotalFATs
BPB_RootEntCnt	DW	0x00E0			;MaxRootEntries
BPB_TotSec16	DW	0x0B40			;TotalSectors
BPB_Media	DB	0xF0				;MediaDescriptor
BPB_FATSz16	DW	0x0009				;SectorsPerFAT
BPB_SecPerTrk	DW	0x0012			;SectorsPerTrack
BPB_NumHeads	DW	0x0002			;NumHeads
BPB_HiddSec	DD	0x00000000			;HiddenSector
BPB_TotSec32	DD	0x00000000		;TotalSectors

BS_DrvNum		DB	0x00			;DriveNumber
BS_Reserved1	DB	0x00			;Reserved
BS_BootSig		DB	0x29			;BootSignature
BS_VolID		DD	0x20090321		;VolumeSerialNumber
BS_VolLab		DB	"MyOS       "	;VolumeLabel
BS_FilSysType	DB	"FAT12   "		;FileSystemType


;***********************************************
; Boot Program
;***********************************************
BOOT:
	CLI			;clears the interrupt flag
	CLC			;clears the carry flag
	CLD			;clears the direction flag
	
; code located at 00007C00, addjust segmen registers
	MOV	AX, 0x07C0
	MOV	DS, AX
	MOV	ES, AX
	MOV	FS, AX
	MOV	GS, AX

	XOR	BX, BX
	XOR	CX, CX
	XOR	DX, DX

; create stack
	XOR	AX, AX
	MOV	SS, AX
	MOV	SP, 0xFFFF
	STI			;sets the interrupt flag(enable IRQ)

;***********************************************
; Load FAT From Floppy
;***********************************************
;LOAD_FAT:
; read FAT into memory (7C000200)
	MOV	BX, WORD [BX_FAT_ADDR]		; FAT buffer
	ADD	AX, WORD [BPB_RsvdSecCnt]
	XCHG	AX, CX
	MOV	AX, WORD [BPB_FATSz16]
	MUL	WORD[BPB_NumHeads]
	XCHG	AX, CX					; CX value is FAT size
READ_FAT:
	call	ReadSector
	ADD	BX, WORD [BPB_BytsPerSec]	; queue next buffer
	INC	AX							; queue next sector
	DEC	CX
	JCXZ	FAT_LOADED
	JMP	READ_FAT

FAT_LOADED:

;***********************************************
; Load Root From Floppy
;***********************************************
LOAD_ROOT:
	MOV	BX, WORD [BX_RTDIR_ADDR]	; ROOT buffer
	XOR	CX, CX
	MOV	WORD [datasector], AX
	XCHG	AX, CX
; compute size of root directory
	MOV	AX, 0x0020					; 32 byte directory entry
	MUL	WORD [BPB_RootEntCnt]
	DIV	WORD [BPB_BytsPerSec]
	XCHG	AX, CX					; CX value has root size
	ADD	WORD [datasector], CX

READ_ROOT:
	call	ReadSector
	ADD	BX, WORD [BPB_BytsPerSec]	; queue next buffer
	INC	AX							; queue next sector
	DEC	CX
	JCXZ	ROOT_LOADED
	JMP	READ_ROOT

ROOT_LOADED:

;***********************************************
; Browse Root directory
;***********************************************
	MOV	BX, WORD [BX_RTDIR_ADDR]
	MOV	CX, WORD [BPB_RootEntCnt]	
	MOV	SI, ImageName
BROWSE_ROOT:
	MOV	DI, BX
	PUSH	CX
	MOV	CX, 0x000B
	PUSH	DI
	PUSH	SI
REPE	CMPSB
	POP	SI
	POP	DI
	JCXZ	BROWSE_FINISHED
	ADD	BX, 0x0020
	POP	CX
; next directory entory	
	LOOP	BROWSE_ROOT
	JMP	FAILURE

BROWSE_FINISHED:
	POP	CX
	
	MOV	AX, WORD [BX+0x001A]
	MOV	BX, WORD[ES_IMAGE_ADDR]
	MOV	ES, BX
	XOR	BX, BX	 
	PUSH	BX
	MOV	WORD [cluster], AX
;***********************************************
; Load Image 
;***********************************************
; save starting cluster of boot image
LOAD_IMAGE:
	MOV	AX, WORD [cluster]
	POP	BX
	CALL	ClusterLBA
	XOR	CX, CX
	MOV	CL, BYTE [BPB_SecPerClus]
	CALL	ReadSector	
	ADD	BX, 0x0200
	PUSH	BX
; compute next cluster
	MOV	AX, WORD [cluster]
	MOV	CX, AX
	MOV	DX, AX
	SHR	DX, 0x0001
	ADD	CX, DX
	MOV	BX, WORD[BX_FAT_ADDR]		; location FAT in memory
	ADD	BX, CX
	MOV	DX, WORD [BX]
	TEST	AX, 0x0001
	JNZ	ODD_CLUSTER
EVEN_CLUSTER:
	AND	DX, 0x0FFF					; take low twelve bits
	JMP	LOCAL_DONE
ODD_CLUSTER:
	SHR	DX, 0x0004					; take high twelve bits
LOCAL_DONE:
	MOV	WORD [cluster], DX			; store newcluster
	CMP	DX, 0x0FF0					; test for end of file
	JB	LOAD_IMAGE
		
ALL_DONE:
	POP	BX
	MOV	SI, msgIMAGEOK
	call 	DisplayMessage
	PUSH	WORD [ES_IMAGE_ADDR]
	PUSH	WORD 0x0000
	;MOV	AX, WORD [ES_IMAGE_ADDR]
	;MOV	DS, AX
	;MOV	ES, AX
	;MOV	FS, AX
	;MOV	GS, AX	
	RETF
;***********************************************
; When Failure
;***********************************************
FAILURE:
	MOV	SI, msgFailure
	CALL	DisplayMessage
	MOV	AH, 0x00
	INT	0x16
	INT	0x19

;***********************************************
; DisplayMessage
; display ASCIIZ string
;***********************************************
DisplayMessage:
	PUSH	AX
	PUSH	BX
StartDispMsg:
	LODSB
	OR	AL, AL
	JZ	.DONE
	MOV	AH, 0x0E
	MOV	BH, 0x00
	MOV	BL, 0x07
	INT	0x10
	JMP	StartDispMsg
.DONE:
	POP	BX
	POP	AX
	RET
;***********************************************
; ReadSector
; Read 1 Sector 
; Input: BX:address  
;      : AX:sector number
;***********************************************
ReadSector:
	MOV	DI, 0x0005					; five retries for error
SECTORLOOP:
	PUSH	AX
	PUSH	BX
	PUSH	CX
	CALL	LBACHS
	MOV	AH, 0x02					; BIOS read sector
	MOV	AL, 0x01					; read one sector
	MOV	CH, BYTE [absoluteTrack]	; track
	MOV	CL, BYTE [absoluteSector]	; secotr
	MOV	DH, BYTE [absoluteHead]		; head
	MOV	DL, BYTE [BS_DrvNum]		; drive
	INT	0x13						; invoke BIOS
	JNC	SUCCESS						; test for read error
	XOR	AX, AX						; BIOS reset disk
	INT	0x13						; invoke BIOS
	DEC	DI							; decrement error counter
	POP	CX
	POP	BX
	POP	AX
	JNZ	SECTORLOOP					; attempt to read again
	INT	0x18
SUCCESS:
	POP	CX
	POP	BX
	POP	AX
	RET
	
;*************************************************************************
; PROCEDURE ClusterLBA
; convert FAT cluster into LBA addressing scheme
; LAB = (cluster - 2 ) * sectors per cluster
; INPUT  : AX : cluster number
; OUTPUT : AX : base image sector
;*************************************************************************
ClusterLBA:
	SUB	AX, 0x0002			; zero base
	XOR	CX, CX
	MOV	CL, BYTE [BPB_SecPerClus]
	MUL	CX
	ADD	AX, WORD [datasector]		; base data sector
	RET

;*************************************************************************
; PROCEDURE LBACHS
; convert &quot;ax2; LBA addressing scheme to CHS addressing scheme
; absolute sector = (logical sector / sectors per track) + 1
; absolute head   = (logical sector / sectors per track) MOD number of heads
; absolute track  = logical sector / (sectors per track * number of heads)
;*************************************************************************
LBACHS:
	XOR	DX, DX				; prepare DX:AX for operation
	DIV	WORD [BPB_SecPerTrk]		; calculate
	INC	DL				; adjust for sector
	MOV	BYTE [absoluteSector], DL	
	XOR	DX, DX				; prepare DX:AX for operation
	DIV	WORD [BPB_NumHeads]		; calculate
	MOV	BYTE [absoluteHead], DL	
	MOV	BYTE [absoluteTrack], AL	
	RET
	



;***********************************************
; Valuable 
;***********************************************
datasector		DW 0x0000
cluster			DW 0x0000
BX_FAT_ADDR		DW 0x0200	; base address 0x000007C00 is assumed
BX_RTDIR_ADDR	DW 0x2600	; base address 0x000007C00 is assumed
ES_IMAGE_ADDR	DW 0x0050	; base address 0x000000500 is assumed

absoluteSector	DB 0x00
absoluteHead	DB 0x00
absoluteTrack	DB 0x00

ImageName	DB "STARTINGIMG", 0x00
msgIMAGEOK	DB "IMAGE is loaded", 0x0D, 0x0A, 0x00
msgFailure	DB "Loading is failure", 0x0D, 0x0A, 0x00

TIMES	510-($-$$) DB 0
DW	0xAA55
