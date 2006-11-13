#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/io.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <fcntl.h>

#include <native/task.h>
#include <native/queue.h>
#include <native/intr.h>
#include <native/pipe.h>

//#define CHECK_TC_LONG

//#define STAT_LOGGIN_RET "\n"
#define STAT_LOGGIN_RET "\r"
//#define FIXED_TESTING_TIME 10


#ifdef CHECK_TC_LONG
#define FPS 25
static unsigned long tc_bcd2frames_mults[8] = 
{
	10 * 3600 * (int)FPS,
	 1 * 3600 * (int)FPS,
	10 *   60 * (int)FPS,
	 1 *   60 * (int)FPS,
	10 *    1 * (int)FPS,
	 1 *    1 * (int)FPS,
	10 *    1 * 1,
	 1 *    1 * 1
};
unsigned long tc_bcd2frames(unsigned long tc_bcd)
{
	unsigned long temp_tc = 0;
	int i;
	for(i=0;i<8;i++,tc_bcd>>=4)
		temp_tc+=tc_bcd2frames_mults[7-i]*(tc_bcd&0xf);
	return temp_tc;
};
#endif /* CHECK_TC_LONG */

/* standart LPT port */
#define PARPORT_INT 7
#define PARPORT_ADR 0x378

/* control port */
#define PARPORT_BIDRECTIONAL		(0x0200 | (1<<5))
#define PARPORT_ENABLE_IRQ_VIA_ACK	(0x0200 | (1<<4))
#define PARPORT_LINE_FEED		(0x0200 | (1<<1))
#define PARPORT_STROBE			(0x0200 | (1<<0))

/* status port */
#define PARPORT_PAPER_OUT		(0x0100 | (1<<5))

/* operations */
#define PARPORT_RISE_BIT(_B, _P)	outb( inb(_P + (_B>>8)) | (_B & 0xFF), _P + (_B>>8))
#define PARPORT_DOWN_BIT(_B, _P)	outb( inb(_P + (_B>>8)) & (0xFF ^ (_B & 0xFF)), _P + (_B>>8))
#define PARPORT_IS_BIT(_B, _P)		(inb(_P + (_B>>8)) & (_B & 0xFF))?1:0


RT_INTR intr;
RT_TASK task;
int f_exit = 0;

static void sighandler (int sig)
{
    fprintf(stderr, "Interrupt event happens\n");
    f_exit = 1;
};

static void video_sync_tc_reader(void* p)
{
    int r,t,f,i;
    unsigned long tc,b,tc_prev;
    long long t1=0, t2=0;

    /* ask for permission to access the parallel port from user-space */
    if (ioperm(PARPORT_ADR, 3 , 1) < 0) 
    {
	fprintf(stderr, "ioperm: error accessing IO-ports");
	f_exit = 1;
	return;
    };

    /* init port */
    outb(0xFF, 						PARPORT_ADR); /* rise all outputs */
    PARPORT_RISE_BIT(PARPORT_BIDRECTIONAL, 		PARPORT_ADR); /* enable bidirectional mode */
    PARPORT_RISE_BIT(PARPORT_ENABLE_IRQ_VIA_ACK, 	PARPORT_ADR); /* enable IRQ via nACK */
    PARPORT_DOWN_BIT(PARPORT_STROBE, 			PARPORT_ADR); /* down STROBE bit */
    PARPORT_DOWN_BIT(PARPORT_LINE_FEED, 		PARPORT_ADR); /* down LINE FEED bit */

    /* loop */
    while(!(f_exit))
    {
	/* enable interrupt */
	rt_intr_enable (&intr);

	/* wait interrupt 22miliseconds*/
	r = rt_intr_wait(&intr, 39700000LL);

	t2 = t1;
	t1 = rt_timer_ticks2ns(rt_timer_read());
    
	/* process irq wait results */
	if(0 < r)			/* interrupt happens */
	{
	    t = 0;
	}
	else if( (-ETIMEDOUT) == r )	/* timeout happens */
	{
	    t = 1;
	}
	else				/* error happens */
	{
	    fprintf(stderr, "Error! 'rt_intr_wait' returned %d\n", r);
	    f_exit = 1;
	    return;
	};

	/* detect field */
	f = PARPORT_IS_BIT(PARPORT_PAPER_OUT, 		PARPORT_ADR);	/* 0 - even - upper(PAL), 1 - odd - lower (PAL) */
	
	/* read tc */
	for(i = 0,tc=0; i<4; i++)
	{
	    if(0 == i)							/* byte #0 */
		PARPORT_RISE_BIT(PARPORT_LINE_FEED,	PARPORT_ADR);
	    PARPORT_RISE_BIT(PARPORT_STROBE,		PARPORT_ADR);	/* up STROBE bit */
	    rt_task_sleep(25000LL);
	    b = inb(PARPORT_ADR);
	    tc |= (b & 0xFF)<<(i*8);
	    PARPORT_DOWN_BIT(PARPORT_STROBE, 		PARPORT_ADR);	/* down STROBE bit */
	    if(0 == i)							/* byte #0 */
		PARPORT_DOWN_BIT(PARPORT_LINE_FEED, 	PARPORT_ADR);	/* down LINE FEED bit */
	    rt_task_sleep(25000LL);
	};

    
	fprintf(stdout, "[%d][%d] = %.8X, %-16lld" STAT_LOGGIN_RET , t, f, tc, (t1 - t2)/1000);
	fflush(stdout);
	
#ifdef CHECK_TC_LONG
	if((tc_bcd2frames(tc) - tc_bcd2frames(tc_prev) ) > 1)
	    fprintf(stderr, "DROPPED: %.8X -> %.8X\n", tc_prev, tc);
	
	tc_prev = tc;

#endif	/* CHECK_TC_LONG */
	
//	if(0x78563412 != tc)
//	    fprintf(stderr, "![%d][%d] = %.8X\n", t, f, tc);
    };

};



int main(int argc, char *argv[]) 
{
    int r, fd, i;
    unsigned int b;

    /* setup SIG handlers */
    signal (SIGINT, sighandler);
    signal (SIGTERM, sighandler);
    signal (SIGPIPE, sighandler);
    signal (SIGHUP, sighandler);
    signal (SIGALRM, sighandler);
    

#ifdef Q
    /* ask for permission to access the parallel port from user-space */
    if (ioperm(PARPORT_ADR, 3 , 1) < 0) 
    {
	fprintf(stderr, "ioperm: error accessing IO-ports");
	exit(-1);
    };

    /* init port */
    outb(0xFF, 						PARPORT_ADR); /* rise all outputs */
    PARPORT_RISE_BIT(PARPORT_BIDRECTIONAL, 		PARPORT_ADR); /* enable bidirectional mode */
    PARPORT_RISE_BIT(PARPORT_ENABLE_IRQ_VIA_ACK, 	PARPORT_ADR); /* enable IRQ via nACK */
    PARPORT_DOWN_BIT(PARPORT_STROBE, 			PARPORT_ADR); /* down STROBE bit */
    PARPORT_DOWN_BIT(PARPORT_LINE_FEED, 		PARPORT_ADR); /* down LINE FEED bit */

	/* read tc */
	for(i = 0; i<4; i++)
	{
	    if(0 == i)							/* byte #0 */
		PARPORT_RISE_BIT(PARPORT_LINE_FEED,	PARPORT_ADR);
	    PARPORT_RISE_BIT(PARPORT_STROBE,		PARPORT_ADR);	/* up STROBE bit */
	    sleep(1);
	    fprintf(stderr, "%.2X\n", inb(PARPORT_ADR));
	    PARPORT_DOWN_BIT(PARPORT_STROBE, 		PARPORT_ADR);	/* down STROBE bit */
	    if(0 == i)							/* byte #0 */
		PARPORT_DOWN_BIT(PARPORT_LINE_FEED, 	PARPORT_ADR);	/* down LINE FEED bit */
	    sleep(1);
	};


    exit(-1);
#endif /* Q */

    /* xenomai tasks */    
    mlockall(MCL_CURRENT | MCL_FUTURE);
    rt_timer_set_mode(TM_ONESHOT);

    /* Create interrupt handler */
    /* CONFIG_XENO_OPT_NATIVE_INTR=y otherwise it fails with ENOSYS (38) */
    if(0 == (r = rt_intr_create(&intr, NULL, PARPORT_INT, I_NOAUTOENA)))
    {
	fprintf(stderr, "IRQ%d handler installed\n", PARPORT_INT);
	
	/* enable interrupt */
//	rt_intr_enable (&intr);

	/* create task for IRQ reading */
        if
        (
    	    0 
    	    == 
    	    (r = rt_task_spawn
    		(
    		    &task,						/* task */
    		    NULL,						/* name */
    		    0,							/* stksize */
    		    50,							/* prio */
    		    T_FPU | T_JOINABLE,					/* mode */
    		    video_sync_tc_reader,				/* entry */
    		    NULL						/* cookie */
    		)
    	    )
    	)
    	{
#ifdef FIXED_TESTING_TIME
	    sleep(10);
	    f_exit = 1;
#else
	    /* sleep loop for end */
	    while(!(f_exit)) usleep(100);
#endif /* FIXED_TESTING_TIME */

	    /* wait task ends */
	    fprintf(stderr, "rt_task_join=%d\n", rt_task_join(&task));
	    fprintf(stderr, "rt_task_delete%d\n", rt_task_delete(&task));
    	}
    	else
    	    fprintf(stderr, "Error! Unable to create task\n");
	
	/* delete interrupt */
	rt_intr_delete(&intr);
    }
    else
	fprintf(stderr, "Error! Unable to install IRQ%d handler\n", PARPORT_INT);

    return 0;
};
