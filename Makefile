CFLAGS=-Wall

all: test-sfp h3prio

fuzz: fuzz-sfp

test-sfp: test-sfp.c ls-sfparser.c ls-sfparser.h
	cc ${CFLAGS} -o test-sfp test-sfp.c ls-sfparser.c

h3prio: h3prio.c ls-sfparser.c ls-sfparser.h
	cc ${CFLAGS} -o h3prio h3prio.c ls-sfparser.c

fuzz-sfp: fuzz-sfp.c ls-sfparser.c ls-sfparser.h
	afl-gcc -O3 -o fuzz-sfp fuzz-sfp.c ls-sfparser.c
	#cc -g3 -o fuzz-sfp fuzz-sfp.c ls-sfparser.c

ls-sfparser.c: ls-sfparser.l
	flex -o ls-sfparser.c ls-sfparser.l

ls-sfparser.c:

clean:
	rm -vf test-sfp fuzz-sfp h3prio
