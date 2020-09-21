# ls-sfparser - Structured Fields Parser in C

## Introduction

ls-sfparser is a [Structured Fields](https://github.com/httpwg/wiki/wiki/Structured-Headers) parser written in C.

Features:
- Simple streaming API
- Simple to include in your projects
- Low on resources
- Portable
- Permissive [MIT License](LICENSE)

## How to Use

The parser is invoked with a single function, `ls_sf_parse()`.  The function is passed the top-level type (Item, List, or Dictionary), the input string and
its size, and the callback function:

```c
    /* Parse HTTP Priority Parameters: */
    const char *input = "u=3, i=?0";
    int ret = ls_sf_parse(LS_SF_TLT_DICTIONARY, input, strlen(input), my_callback,
                                                &prio, NULL, 0);
    if (ret == 0)
        printf("parsing successful\n");
```

The callback may look like this:

```c
/* Return 0 on success, any other value to stop parsing and return with failure. */
static int
my_callback (void *user_data, enum ls_sf_dt type, char *str, size_t len, int off)
{
    struct prio *const prio = user_data;
/* --- 8< --- snip --- 8< --- */
        if (type == LS_SF_DT_INTEGER)
        {   
            prio->urgency = atoi(str);
            if (prio->urgency <= 7)
                prio->flags |= URG_SET;
            else
            {
                printf("invalid value of urgency: %.*s\n", (int) len, str);
                return -1;  
            }
/* --- 8< --- snip --- 8< --- */
}
```

And that's it!  (For full HTTP Priority Properties example, see [h3prio.c](h3prio.c)).  The callback just keeps on getting called
for each data type until the callback returns a non-zero value, until the end of input, or until a parsing error occurs.
`ls_sf_parse()` returns 0 on success and a negative value on failure.

Creation of in-memory structures to represent the parsed Structured Fields and [base64-decoding](
https://tools.ietf.org/html/draft-ietf-httpbis-header-structure-19#section-4.2.7) of Byte Sequences are left as an exercise for the
caller.  There are two reasons for making this design choice:
1. Simplicity.  This parser can be used as a foundation for any Structured Fields representation of your choice.
1. Efficiency.  No reason to base64-decode something before knowing whether it is needed at all.

Please see some additional notes in the relatively short [header file](ls-sfparser.h).

## How to Include in Your Project

Just copy [ls-sfparser.h](ls-sfparser.h) and [ls-sfparser.c](ls-sfparser.c) into your source tree.

## Memory Management

The last two arguments to `ls_sf_parse()` may be used to pass a scratch space buffer for the parser to use.  (Otherwise, it allocates
the memory it needs dynamically.)  Now the parser does not call `malloc(3)` at all!

`ls_sf_parse()` returns -2 if a memory allocation error occurs.  If the buffer you pass is too small, the parser just may run out.
This is a design feature.

## Development

This is a [flex](https://en.wikipedia.org/wiki/Flex_(lexical_analyser_generator))-generated parser with some modifications.
The post-generation alterations to the C source code have to do with memory management.  The code has been changed to return
an error instead of calling `yy_fatal_error()`, which is an awkward way to handle memory allocation failures.
