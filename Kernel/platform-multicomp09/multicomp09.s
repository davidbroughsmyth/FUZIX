;;;
;;; Multicomp 6809 FPGA-based computer
;;;
;;;    low level routines, but not the tricky ones.
;;;    see tricks.s for those.

;;; coco3:
;;; $ff91 writeonly
;;; $ffa0
;;; $ff90
;;; $ffd9   high-speed poke
;;; $ff9c   scroll register
;;; $ffae   super basic in MMU
;;; $c033   BASIC mirror of video reg
;;; $ff98   video row setup
;;; $ff99   video col setup
;;; $ff9d   video map setup
;;; $ffb0   video colour
;;; $ffb0   video colour
;;; $ffb8   video colour
;;; $ffb0   video colour
;;; $ffb0   video colour

;;; coco3 MMU
;;; accessed through registers $ff91 and $ffa0-$ffa7
;;; 2 possible memory maps: map0, map1 selected by $ff91[0]
;;; map0 is used for Kernel mode, map1 is used for User mode.
;;; map1 is selected at boot (ie, now).
;;; when 0, select map0 using pages stored in $ffa0-$ffa7
;;; when 1, select map1 using pages stored in $ffa8-$ffaf
;;; a 512K system has 64 blocks, numbered $00 to $3f
;;; write the block number to the paging register. On readback,
;;; only bits 5:0 are valid; the other bits can contain junk.

;;; multicomp09 MMU
;;; accessed through two WRITE-ONLY registers MMUADR, MMUDAT
;;; 2 possible memory maps: map0, map1 selected by MMUADR[6]
;;; map0 is used for Kernel mode, map1 is used for User mode.
;;; map0 is selected at boot (ie, now)
;;; [NAC HACK 2016Apr23] to avoid pointless divergence from
;;; coco3, the first hardware setup step will be to flip to
;;; map1.
;;; [NAC HACK 2016Apr23] in the future, may handle this in
;;; forth or in the bootstrap
;;; when 0, select map0 using MAPSEL values 0-7
;;; when 1, select map1 using MAPSEL values 8-15
;;; MAPSEL is MMUADR[3:0]
;;; a  512K system has  64 blocks, numbered $00 to $3f
;;; a 1024K system has 128 blocks, numbered $00 to $7f
;;; Write the block number to MMUDAT[6:0]
;;; MMUDAT[7]=1 write-protects the selected block - NOT USED HERE!

;;; coco3: at the time the boot loader passes control this the code here,
;;; map1 is selected (Kernel space) and the map1 mapping
;;; registers are selecting blocks 0-7.
;;; map0 is selecting blocks $38-$3f.

;;; multicomp09: at the time the boot loader passes control this the code here,
;;; map0 is selected (user space) and the map0 mapping
;;; registers are selecting blocks 0-7.
;;; map1 mapping registers are uninitialised.


;;; multicomp09 HW registers
MMUADR	equ	$ffde
MMUDAT	equ	$ffdf

;;; bit-fields
MMUADR_ROMDIS	equ $80		; 0 after reset, 1 when FUZIX boots. Leave at 1.
MMUADR_TR	equ $40		; 0 after reset, 0 when FUZIX boots. 0=map0, 1=map1
MMUADR_MMUEN	equ $20		; 0 after reset, 1 when FUZIX boots. Leave at 1.
MMUADR_NMI	equ $10		; 0 after reset, 0 when FUZIX boots. Do not write 1.
MMUADR_MAPSEL	equ $0f		; last-written value is UNDEFINED.
;;; the only two useful values for the upper nibble
MMU_MAP0	equ	(MMUADR_ROMDIS|MMUADR_MMUEN)
MMU_MAP1	equ	(MMUADR_ROMDIS|MMUADR_MMUEN|MMUADR_TR)


            .module multicomp09

            ; exported symbols
            .globl init_early
            .globl init_hardware
            .globl interrupt_handler
            .globl _program_vectors
	    .globl map_kernel
	    .globl map_process
	    .globl map_process_always
	    .globl map_save
	    .globl map_restore
	    .globl _need_resched
	    .globl _hz
	    .globl _bufpool
	    .globl _discard_size
            .globl _krn_mmu_map
            .globl _usr_mmu_map

            ; exported debugging tools
            .globl _trap_monitor
	    .globl _trap_reboot
            .globl outchar
	    .globl _di
	    .globl _ei
	    .globl _irqrestore

            ; imported symbols
            .globl _ramsize
            .globl _procmem
            .globl unix_syscall_entry
	    .globl nmi_handler
	    .globl null_handler

            include "kernel.def"
            include "../kernel09.def"


	.area	.buffers

_bufpool:
	.ds	BUFSIZE*NBUFS

	.area	.discard
_discard_size:
	.db	__sectionlen_.discard__/BUFSIZE

; -----------------------------------------------------------------------------
; COMMON MEMORY BANK
; -----------------------------------------------------------------------------
            .area .common


saved_tr
	.db 0		; the saved state of the TR bit etc (MMU_MAP0 or MMUMAP1)
curr_tr
	.db 0		; the current state of the TR bit etc (MMU_MAP0 or MMUMAP1)
_need_resched
	.db 0		; scheduler flag

;;; multicomp09 mmu registers are write-only so need to store
;;; a copy of the mappings.
;;; Each byte represents one of the physical address quadrants.
;;; a stored value of N means that 8K RAM pages N and N+1 are assigned to
;;; that quadrant.
;;; Need to write these values any time we're changing the MMU mapping.. UNLESS
;;; it's clear that the routine is subsequently going to restore a value that is
;;; currently stored here.
_krn_mmu_map
	.db	0,2,4,6
_usr_mmu_map
	.db	0,2,4,6


_trap_monitor:
	orcc	#0x10
	bra	_trap_monitor

_trap_reboot:
	orcc 	#0x10		; turn off interrupts
	lda	#0x38		; put RAM block in memory
	sta	0xffa8		;
	;; copy reboot bounce routine down
	ldx	#0		;
	ldu	#bounce@
loop@	lda	,u+
	sta	,x+
	cmpu	#bounce_end@
	bne	loop@
	jmp	0		;
	;; this code is PIC and gets copied down to
	;; low memory on reboot to bounce to the reset
	;; vector.
bounce@
	;; [NAC HACK 2016May01] todo
	lda	#0x06		; reset GIME (map in internal 32k rom)
	sta  	0xff90
	clr	0xff91
	clr	0x72
	jmp	[0xfffe]	; jmp to reset vector
bounce_end@



;;; Turn off interrupts
;;;    takes: nothing
;;;    returns: B = original irq (cc) state
_di:
	tfr	cc,b		; return the old irq state
	orcc	#0x10
	rts

;;; Turn on interrupts
;;;   takes: nothing
;;;   returns: nothing
_ei:
	andcc	#0xef
	rts

;;; Restore interrupts to saved setting
;;;   takes: B = saved state (as returned from _di )
;;;   returns: nothing
_irqrestore:			; B holds the data
	tfr	b,cc
	rts

; -----------------------------------------------------------------------------
; KERNEL MEMORY BANK
; -----------------------------------------------------------------------------
	.area	.data
_hz:	.db	0  		; Is machine in 50hz?


        .area .discard

;;;  Stuff to initialize *before* hardware
;;;    takes: nothing
;;;    returns: nothing
init_early:
	ldx	#null_handler	; [NAC HACK 2016Apr23] what's this for??
	stx	1
	lda	#0x7E
	sta	0
        rts



;;; Initialize Hardware !
;;;    takes: nothing
;;;    returns: nothing
init_hardware:
	;; [NAC HACK 2016Apr23] todo: size the memory. For now, assume 512K like coco3
	;; set system RAM size
	ldd 	#512
	std 	_ramsize
	ldd 	#512-64
	std 	_procmem


;;; [NAC HACK 2016Apr23] coco3 at this point sets up physical blocks 0-7 for user mode.
;;; ..which is the same mapping that is in use for kernel mode.

;;; multicomp09 currently has map0 selected and blocks 0-7 mapped.
;;; To match the coco3 set-up need to select blocks 0-7 for map1 then switch to map1.
;;; Want to end with _krn_mmu_map and _usr_mmu_map and curr_tr all correct.
;;; 

;;; [NAC HACK 2016May01] todo
	;; set up the map1 registers (MAPSEL=8..f) to use pages 0-7
	;; ..to match the pre-existing setup of map0.
	;; while doing this, were careful to keep MMUADR_MAP1 *clear* because we are using
	;; map0 and don't want to switch the map yet.
	lda	#(MMU_MAP0|8)	; stay in map0, select 1st mapping register for map1
	ldy	#MMUADR

	ldx	#_krn_mmu_map
	ldb	,x+	   	; page from krn_mmu_map
	std	,y		; select MAPSEL and immediately write MMUDAT mapsel=8
	inca			; next mapsel
	incb			; adjacent page
	std	,y		; select MAPSEL and immediately write MMUDAT mapsel=9

	inca			; next mapsel
	ldb	,x+		; page from krn_mmu_map
	std	,y		; select MAPSEL and immediately write MMUDAT mapsel=a
	inca			; next mapsel
	incb		   	; adjacent page
	std	,y		; select MAPSEL and immediately write MMUDAT mapsel=b

	inca			; next mapsel
	ldb	,x+		; page from krn_mmu_map
	std	,y		; select MAPSEL and immediately write MMUDAT mapsel=c
	inca			; next mapsel
	incb			; adjacent page
	std	,y		; select MAPSEL and immediately write MMUDAT mapsel=d

	inca			; next mapsel
	ldb	,x+		; page from krn_mmu_map
	std	,y		; select MAPSEL and immediately write MMUDAT mapsel=e
	inca			; next mapsel
	incb			; adjacent page
	std	,y		; select MAPSEL and immediately write MMUDAT mapsel=f

	;; swap to map1
	;; the two labels generate entries in the map file that are useful
	;; when debugging: did we get past this step successfully.
gomap1:	lda	#MMU_MAP1
	sta	,y
	sta	curr_tr
atmap1:	nop


	;; Multicomp09 has RAM up at the hardware vector positions
	;; so we can write the addresses directly, 2 bytes per vector;
	;; no need for a jump op-code.
	ldx	#0xfff2		; address of SWI3 vector
	ldy	#badswi_handler
	sty	,x++		; SWI3 handler
	sty	,x++		; SWI2 handler
	ldy	#firq_handler
	sty	,x++		; FIRQ handler
	ldy	#my_interrupt_handler
	sty	,x++		; IRQ  handler
	ldy	#unix_syscall_entry
	sty	,x++		; SWI  handler
	ldy	#nmi_handler
	sty	,x++		; NMI  handler

	jsr	_devtty_init
xinihw:	rts


;------------------------------------------------------------------------------
; COMMON MEMORY PROCEDURES FOLLOW

	.area .common

;;; Platform specific userspace setup
;;;   We're going to borrow this to copy the common bank
;;;   into the userspace too.
;;;   takes: X = page table pointer
;;;   returns: nothing
;;; [NAC HACK 2016May01] but.. X (page table pointer) not used??
;;; [NAC HACK 2016May01] this can be smaller and tidier. Point to MMUADR and do indexed access.
_program_vectors:
	;; copy the common section into user-space
	pshs	x,u

	;; setup the null pointer / sentinal bytes in low process memory
	lda	#(MMU_MAP1|8)
	sta	MMUADR

	lda	[1,s]	     ; get process's blk address for address 0
	sta	MMUDAT	     ; put in our mmu ( at address 0 )
	lda	#0x7E
	sta	0

	;; restore the MMU mapping that we trampled on
	lda	#(MMU_MAP1|8)
	sta	MMUADR
	lda	_krn_mmu_map
	sta	MMUDAT

	puls	pc,x,u	     ; restore reg and return

;;; This clear the interrupt source before calling the
;;; normal handler
;;;    takes: nothing ( it is an interrupt handler)
;;;    returns: nothing ( it is an interrupt handler )
my_interrupt_handler
;	lda	$ff02		; clear pia irq latch by reading data port
	jmp	interrupt_handler ; jump to regular handler

;;;  FIXME:  these interrupt handlers should prolly do something
;;;  in the future.
firq_handler:
badswi_handler:
	rti


;;; Userspace mapping pages 7+  kernel mapping pages 3-5, first common 6
;;; All registers preserved
map_process_always:
	pshs	x,y,u
	ldx	#U_DATA__U_PAGE
	jsr	map_process_2
	puls	x,y,u,pc

;;; Maps a page table into cpu space
;;;   takes: X - pointer page table ( ptptr )
;;;   returns: nothing
;;;   modifies: nothing
map_process:
	cmpx	#0		; is zero?
	bne	map_process_2	; no then map process; else: map the kernel
	;; !!! fall-through to below

;;; Maps the Kernel into CPU space
;;;   takes: nothing
;;;   returns: nothing
;;;   modifies: nothing
;;;	Map in the kernel below the current common, all registers preserved
map_kernel:
	pshs	a
	lda	#MMU_MAP1	; flip to mmu map 1 (kernel)
	sta	MMUADR
	sta	curr_tr		; save copy
	puls 	a,pc

;;; User is in MAP0 with the top 8K as common
;;; As the core code currently does 16K happily but not 8 we just pair
;;; up pages

;;; Maps a page table into the MMU
;;;   takes: X = pointer to page table
;;;   returns: nothing
;;;   modifies: nothing
map_process_2:
	pshs	x,y,a

	;; first copy 4 entries from page table to usr_mmu_map
	ldy	#_usr_mmu_map
	lda	,x+		; get byte from page table
	sta	0,y		; copy to usr_mmu_map
	lda	,x+		; get byte from page table
	sta	1,y		; copy to usr_mmu_map
	lda	,x+		; get byte from page table
	sta	2,y		; copy to usr_mmu_map
	lda	,x+		; get byte from page table
	sta	3,y		; copy to usr_mmu_map
;;; [NAC HACK 2016May01] revamp init code above to swap x,y to match this.
	;; now, update MMU with those values
	lda	#(MMU_MAP1|0)	; stay in map1, select mapsel=0
	ldx	#MMUADR

	ldb	,y+		; page from usr_mmu_map
	std	,x		; select MAPSEL and immediately write MMUDAT mapsel=0
	inca			; next mapsel
	incb			; adjacent page
	std	,x		; select MAPSEL and immediately write MMUDAT mapsel=1

	inca			; next mapsel
	ldb	,y+		; page from usr_mmu_map
	std	,x		; select MAPSEL and immediately write MMUDAT mapsel=2
	inca			; next mapsel
	incb		   	; adjacent page
	std	,x		; select MAPSEL and immediately write MMUDAT mapsel=3

	inca			; next mapsel
	ldb	,y+		; page from usr_mmu_map
	std	,x		; select MAPSEL and immediately write MMUDAT mapsel=4
	inca			; next mapsel
	incb			; adjacent page
	std	,x		; select MAPSEL and immediately write MMUDAT mapsel=5

	inca			; next mapsel
	ldb	,y+		; page from usr_mmu_map
	std	,x		; select MAPSEL and immediately write MMUDAT mapsel=6
	;; bank all but common memory.

	lda	#MMU_MAP0
	sta	,x		; new mapping goes live here
	sta	curr_tr		; and remember new TR setting
	puls	x,y,a,pc	; so had better include common!

;;;
;;;	Restore a saved mapping. We are guaranteed that we won't switch
;;;	common copy between save and restore. Preserve all registers
;;;
;;;	We cheat somewhat. We have two mapping sets, so just remember
;;;	which space we were in. Note: we could be in kernel in either
;;;	space while doing user copies
;;;
map_restore:
	pshs	a
	lda	saved_tr
	sta	curr_tr
	sta	MMUADR
	puls	a,pc

;;; Save current mapping
;;;   takes: nothing
;;;   returns: nothing
map_save:
	pshs	a
	lda	curr_tr
	sta	saved_tr
	puls	a,pc

;;; Maps the memory for swap transfers
;;;   takes: A = swap token ( a page no. )
;;;   returns: nothing
;;; [NAC HACK 2016May01] maps 16K into kernel space
map_for_swap
	ldb	curr_tr
	orb	#8
	stb	MMUADR		; select first 8K in kernel mapping mapsel=8
	sta	MMUDAT
	incb
	stb	MMUADR		; select second 8K in kernel mapping mapsel=9
	sta	MMUDAT
	rts

;;; multicomp09 HW registers
;;; vdu/virtual UART
UARTDAT	equ $ffd1
UARTSTA	equ $ffd0

;;;  Print a character to debugging
;;;   takes: A = character
;;;   returns: nothing
outchar:
	pshs    b,cc
vdubiz  ldb     UARTSTA
        bitb    #2
        beq     vdubiz	; busy

	sta	UARTDAT	; ready, send character
	puls	b,cc,pc
