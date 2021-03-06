#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ls-sfparser.h"


static int
callback (void *input, enum ls_sf_dt type, char *str, size_t len, int off)
{
    printf("type: %s; str: `%s'; len: %zd; off: %d\n", ls_sf_dt2str[type],
                                                                str, len, off);
    if (off >= 0)
    {
        if (0 != memcmp(input + off, str, len))
        {
            printf("error: offset\n");
            return -1;
        }
    }
    else if (!(type == LS_SF_DT_BOOLEAN && len == 1 && str[0] == '1'))
    {
        printf("error: expected boolean 1\n");
        return -1;
    }

    return 0;
}


int
main (int argc, char **argv)
{
    int ret, tlt;
    char *input;
    size_t input_sz;
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

    if (argc == 3)
    {
        input = argv[2];
        input_sz = strlen(argv[2]);
    }
    else
    {
        input_sz = fread(buf, 1, sizeof(buf), stdin);
        input = buf;
    }

    ret = ls_sf_parse((enum ls_sf_tlt) tlt, input, input_sz, callback,
                                                input, mem, sizeof(mem));
    return ret == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
