CC=gcc
CFLAGS=-I.
DEPS = policyfile_lib.h
OBJ = test.o policyfile_lib.o

%.o: %.c $(DEPS)
	$(CC) -Wall -c -o $@ $< $(CFLAGS)

test: $(OBJ)
	gcc -Wall -o $@ $^ $(CFLAGS)

clean:
	rm -f test test.o policyfile_lib.o
