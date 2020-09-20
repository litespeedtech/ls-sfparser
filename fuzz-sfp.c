#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ls-sfparser.h"


static int
callback (void *user_data, enum ls_sf_dt type, char *str, size_t len, int off)
{
    return 0;
}


int
main (int argc, char **argv)
{
    int ret, tlt;
    char *input;
    size_t input_sz;
    FILE *file;
    char buf[0x10000];
    char mem[0x4000];

    if (argc != 3 && argc != 2)
    {
  usage:
        printf(
"Usage: %s top-level-type [string]\n"
"\n"
"<top-level-type> is a number:\n"
"   0       Dictionary\n"
"   1       List\n"
"   2       Item\n"
"\n"
"Examine exit status to see whether <string> parsed correctly.\n"
"If <string> is not specified, read input from stdin.\n"
"\n", argv[0]);
        return EXIT_FAILURE;
    }

    tlt = atoi(argv[1]);
    if (!(tlt >= 0 && tlt <= 2))
        goto usage;

    file = fopen(argv[2], "rb");
    if (!file)
        exit(EXIT_FAILURE);

    input_sz = fread(buf, 1, sizeof(buf), file);
    if (input_sz == 0)
        exit(EXIT_FAILURE);
    input = buf;

    ret = ls_sf_parse((enum ls_sf_tlt) tlt, input, input_sz, callback,
                                                NULL, mem, sizeof(mem));
    fclose(file);
    return ret == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
