;;;
;;; A Fuzix booter for the multicomp09 SDcard controller.
;;;
;;; Neal Crook April 2016
;;; This code started as a frankensteinian fusion of Brett's Coco3
;;; booter and my FLEX bootstrap loader.
;;;
;;; This booter is <1 512-byte sectors long and can live anywhere on
;;; SD. It is loaded to 0xd000 and entered from there. It uses a
;;; 512byte disk buffer beyond its end point and a 100-byte stack
;;; beyond that.. so its whole footprint is <1Kbyte.
;;;
;;; Environment: at entry, the multicomp ROM is disabled and the
;;; MMU is enabled and is set up for a flat (1-1) mapping, with TR=0.
;;; Function: load and start a DECB image (the FUZIX kernel). The
;;; location of the image on the SDcard is hard-wired by equates
;;; klba2..klba0 below.

;;; [NAC HACK 2016Apr22] todo: don't actually NEED a disk buffer..
;;; do without it.. but then need a routine to flush the remaining
;;; data (if any) from the SDcard after the last sector's done
;;; with and before jumping into the loaded image.

;;; --------- multicomp i/o registers

;;; sdcard control registers
sddata	equ $ffd8
sdctl	equ $ffd9
sdlba0	equ $ffda
sdlba1	equ $ffdb
sdlba2	equ $ffdc

;;; vdu/virtual UART
uartdat	equ $ffd1
uartsta	equ $ffd0

klba2	equ $3
klba1	equ $0
klba0	equ $0

;;; based on the memory map, this seems a safe place to load; the
;;; kernel doesn't use any space here. That may change and require
;;; a re-evaluation.
	org	$d000

;;; entry point
start	lds	#stack

	lda	#'F'		; show user that we got here
	bsr	tovdu
	lda	#'U'
	bsr	tovdu
	lda	#'Z'
	bsr	tovdu
	lda	#'I'
	bsr	tovdu
	lda	#'X'
	bsr	tovdu

;;; decb format:
;;;
;;; section preamble:
;;; offset 0 0x00
;;;	   1 length high
;;;	   2 length low
;;;	   3 load address high
;;;	   4 load address low
;;;
;;; image postamble:
;;; offset 0 0xff
;;;	   1 0x00
;;;	   2 0x00
;;;	   3 exec high
;;;	   4 exec low

;;; Y - preserved as pointer to disk buffer. Start at empty
;;; buffer to trigger a disk load.
	ldy	#sctbuf+512

c@	jsr	getb		; get a byte in A from buffer
	cmpa	#$ff		; postamble marker?
	beq	post		; yes, handle it and we're done.
	;; expect preamble
	cmpa	#0		; preamble marker?
	lbne	abort		; unexpected.. bad format
	jsr	getw		; D = length
	tfr	d,x		; X = length
	jsr	getw		; D = load address
	tfr	d,u		; U = load address
	;; load section: X bytes into memory at U
d@	jsr	getb		; A = byte
	sta	,u+		; copy to memory
	leax	-1,x		; decrement byte count
	bne	d@		; loop for next byte if any
	bra	c@		; loop for next pre/post amble
	;; postable
post	jsr	getw		; get zero's
	cmpd	#0		; test D.. expect 0
	lbne	abort		; unexpected.. bad format
	jsr	getw		; get exec address
	pshs	d		; save on stack
	rts			; go and never come back


;;; Abort! Bad record format.
abort	lda	#'B'		; show user that we got here
	bsr	tovdu
	lda	#'A'
	bsr	tovdu
	lda	#'D'
	bsr	tovdu
	lda	#$0d
	bsr	tovdu
	lda	#$0a
	bsr	tovdu
abort1	bra	abort1		; spin forever


;;;
;;; SUBROUTINE ENTRY POINT
;;; send character to vdu
;;; a: character to print
;;; can destroy b,cc

tovdu	pshs	b
vdubiz	ldb	uartsta
	bitb	#2
	beq	vdubiz	; busy

	sta	uartdat	; ready, send character
	puls	b,pc


;;;
;;; SUBROUTINE ENTRY POINT
;;; get next word from disk buffer - read sector/refill buffer
;;; if necessary
;;; return word in D
;;; must preserve Y which is a global pointing to the next char in the buffer

getw	jsr	getb		; A = high byte
	tfr	a,b		; B = high byte
	jsr	getb		; A = low byte
	exg	a,b		; flip D = next word
	rts


;;;
;;; SUBROUTINE ENTRY POINT
;;; get next byte from disk buffer - read sector/refill buffer
;;; if necessary
;;; return byte in A
;;; Destroys A, B.
;;; must preserve Y which is a global pointing to the next char in the buffer

getb	cmpy	#sctbuf+512	; out of data?
	bne	getb4		; go read byte if not
getb2	bsr	read		; read next sector, reset Y
	ldd	lba1		; point to next linear block
	addd	#1
	std	lba1
getb4	lda	,y+		; get next character
	rts


;;;
;;; SUBROUTINE ENTRY POINT
;;; read single 512-byte block from lba0, lba1, lba2 to
;;; buffer at sctbuf.
;;; return Y pointing to start of buffer.
;;; Destroys A, B
;;;

read	lda	lba0		; load block address to SDcontroller
	sta	sdlba0
	lda	lba1
	sta	sdlba1
	lda	lba2
	sta	sdlba2

	clra
	sta	sdctl		; issue RD command to SDcontroller

	ldy	#sctbuf		; where to put it

;;; now transfer 512 bytes, waiting for each in turn.

	clrb			; zero is like 256
sdbiz	lda	sdctl
	cmpa	#$e0
	bne	sdbiz		; byte not ready
	lda	sddata		; get byte
	sta	,y+		; store in sector buffer
	decb
	bne	sdbiz		; next

	;; b is zero (like 256) so ready to spin again
sdbiz2	lda	sdctl
	cmpa	#$e0
	bne	sdbiz2		; byte not ready
	lda	sddata		; get byte
	sta	,y+		; store in sector buffer
	decb
	bne	sdbiz2		; next

	lda	#'.'		; indicate load progress
	lbsr	tovdu

	ldy	#sctbuf		; where next byte will come from
	rts

;;; location on SDcard of kernel
;;; hack!! The code here assumes NO WRAP from lba1 to lba2.
lba2	.db     klba2
lba1	.db     klba1
lba0	.db     klba0



sctbuf	equ	.
	.ds	512		; SDcard sector buffer
	.ds	100		; space for stack
stack	equ	.

	end	start
