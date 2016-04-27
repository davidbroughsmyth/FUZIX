#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <stdbool.h>
#include <devtty.h>
#include <device.h>
#include <vt.h>
#include <tty.h>
#include <devdw.h>
#include <ttydw.h>
#include <graphics.h>

#undef  DEBUG			/* UNdefine to delete debug code sequences */


/* [NAC HACK 2016Apr23] hack to allow linking.. needs fixing!! */
int vt_ioctl(uint8_t minor, uarg_t request, char *data) { return 0; }


/* Multicomp has 3 serial ports. Each is a cut-down 6850, with fixed BAUD rate and word size.
   Port 0 is, by default, a virtual UART interface to a VGA output and PS/2 keyboard
   Port 1 is, by default, a serial port
   Port 0 and Port 1 mappings can be swapped through a jumper on the PCB.
   Port 2 is a serial port.

   Port 0 is used for tty1, Port 1 for tty2.
*/
static uint8_t *uart[] = {
    0,      0,                               /* Unused */
    (uint8_t *)0xFFD1, (uint8_t *)0xFFD0,    /* Virtual UART Data, Status port0, tty1 */
    (uint8_t *)0xFFD3, (uint8_t *)0xFFD2,    /*         UART Data, Status port1, tty2 */
    (uint8_t *)0xFFD5, (uint8_t *)0xFFD4,    /*         UART Data, Status port2, tty3 */
};


#define VSECT __attribute__((section(".video")))
#define VSECTD __attribute__((section(".videodata")))


/* [NAC HACK 2016Apr24] to go? */
extern uint8_t hz;


uint8_t vtattr_cap;


uint8_t tbuf1[TTYSIZ];   /* virtual serial port 0: console */
uint8_t tbuf2[TTYSIZ];   /*         serial port 1: UART */
uint8_t tbuf3[TTYSIZ];   /*         serial port 2: UART */
uint8_t tbuf4[TTYSIZ];   /* drivewire VSER 0 */
uint8_t tbuf5[TTYSIZ];   /* drivewire VSER 1 */
uint8_t tbuf6[TTYSIZ];   /* drivewire VSER 2 */
uint8_t tbuf7[TTYSIZ];   /* drivewire VSER 3 */
uint8_t tbuf8[TTYSIZ];   /* drivewire VWIN 0 */
uint8_t tbuf9[TTYSIZ];   /* drivewire VWIN 1 */
uint8_t tbufa[TTYSIZ];   /* drivewire VWIN 2 */
uint8_t tbufb[TTYSIZ];   /* drivewire VWIN 3 */


struct s_queue ttyinq[NUM_DEV_TTY + 1] = {
	/* ttyinq[0] is never used */
	{NULL, NULL, NULL, 0, 0, 0},
	/* Virtual UART/Real UART Consoles */
	{tbuf1, tbuf1, tbuf1, TTYSIZ, 0, TTYSIZ / 2},
	{tbuf2, tbuf2, tbuf2, TTYSIZ, 0, TTYSIZ / 2},
	{tbuf3, tbuf3, tbuf3, TTYSIZ, 0, TTYSIZ / 2},
	/* Drivewire Virtual Serial Ports */
	{tbuf4, tbuf4, tbuf4, TTYSIZ, 0, TTYSIZ / 2},
	{tbuf5, tbuf5, tbuf5, TTYSIZ, 0, TTYSIZ / 2},
	{tbuf6, tbuf6, tbuf6, TTYSIZ, 0, TTYSIZ / 2},
	{tbuf7, tbuf7, tbuf7, TTYSIZ, 0, TTYSIZ / 2},
	/* Drivewire Virtual Window Ports */
	{tbuf8, tbuf8, tbuf8, TTYSIZ, 0, TTYSIZ / 2},
	{tbuf9, tbuf9, tbuf9, TTYSIZ, 0, TTYSIZ / 2},
	{tbufa, tbufa, tbufa, TTYSIZ, 0, TTYSIZ / 2},
	{tbufb, tbufa, tbufa, TTYSIZ, 0, TTYSIZ / 2},
};



/* current minor for input */
int curminor = 1;


/* A wrapper for tty_close that closes the DW port properly */
int my_tty_close(uint8_t minor)
{
	if (minor > 2 && ttydata[minor].users == 1)
		dw_vclose(minor);
	return (tty_close(minor));
}


/* Output for the system console (kprintf etc) */
void kputchar(char c)
{
	if (c == '\n')
		tty_putc(1, '\r');
	tty_putc(1, c);
}

ttyready_t tty_writeready(uint8_t minor)
{
	uint8_t c;
        if ((minor < 1) || (minor > 3)) {
            return TTY_READY_NOW;
        }
	c = *(uart[minor*2 + 1]); /* 2 entries per UART, +1 to get STATUS */
	return (c & 2) ? TTY_READY_NOW : TTY_READY_SOON; /* TX DATA empty */
}

void tty_putc(uint8_t minor, unsigned char c)
{
	if ((minor > 0) && (minor < 4)) {
		*(uart[minor*2]) = c; /* UART Data */
	}
	if (minor > 3 ) {
		dw_putc(minor, c);
	}
}

void tty_sleeping(uint8_t minor)
{
	used(minor);
}


void tty_setup(uint8_t minor)
{
	if (minor > 2) {
		dw_vopen(minor);
		return;
	}
}


int tty_carrier(uint8_t minor)
{
	if( minor > 2 ) return dw_carrier( minor );
	return 1;
}

void tty_interrupt(void)
{

}



void platform_interrupt(void)
{
	timer_interrupt();
	dw_vpoll();
}

int gfx_ioctl(uint8_t minor, uarg_t arg, char *ptr)
{
	if ( minor > 3 )	/* remove once DW get its own ioctl() */
		return tty_ioctl(minor, arg, ptr);
	if (arg >> 8 != 0x03)
		return vt_ioctl(minor, arg, ptr);
	switch( arg ){
	case GFXIOC_GETINFO:
		return 0; //[NAC HACK 2016Apr24] 
	case GFXIOC_GETMODE:
		{
			uint8_t m=ugetc(ptr);
			if( m > 4 ) goto inval;
			return 0; //[NAC HACK 2016Apr24] 
		}
	case GFXIOC_SETMODE:
		{
			return 0; //[NAC HACK 2016Apr24] 
		}
	case GFXIOC_DRAW:
	case GFXIOC_WRITE:
	case GFXIOC_READ:
		{
			return 0; // [NAC HACK 2016Apr24] 
		}
	default:
		break;
	}

	udata.u_error = ENOTTY;
	return -1;

inval:	udata.u_error = EINVAL;
	return -1;
}


/* Initial Setup stuff down here. */

__attribute__((section(".discard")))
void devtty_init()
{
	/* Reset each UART by write to STATUS register */
	*uart[3] = 3;
	*uart[5] = 3;
	*uart[7] = 3;
}
