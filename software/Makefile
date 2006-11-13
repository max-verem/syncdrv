DEBUG=-g3 -ggdb3

XENOMAI=/usr/local/xenomai

XENOMAI_CFLAGS=-I$(XENOMAI)/include
XENOMAI_LDFLAGS=-lnative -L$(XENOMAI)/lib

CFLAGS=$(DEBUG) $(XENOMAI_CFLAGS)
LDFLAGS=$(DEBUG) $(XENOMAI_LDFLAGS)

TARGET=syncdrv_tester
OBJS=main.o

all: $(TARGET)

syncdrv_tester: $(OBJS) 
	$(CC) -o $@ $(OBJS) $(LDFLAGS)

.c.o: $<
	$(CC) -c -o $@ $< $(CFLAGS)

clean:
	rm -f $(TARGET)
	rm -f svnversion.h
	rm -f *.o *~

