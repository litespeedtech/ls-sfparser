/*
MIT License

Copyright (c) 2020 LiteSpeed Technologies Inc

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/* The LiteSpeed Structured Fields Parser parses structured fields decribed in
 * https://tools.ietf.org/html/draft-ietf-httpbis-header-structure-19
 *
 * It provides a simple streaming interface which allows the user to process
 * structured fields in any manner.
 */

#ifndef LS_SFPARSER_H
#define LS_SFPARSER_H 1

enum ls_sf_dt
{   /* LS SF DT: LiteSpeed Structured Field Data Type */
    LS_SF_DT_INTEGER,
    LS_SF_DT_DECIMAL,
    LS_SF_DT_NAME,
    LS_SF_DT_PARAM_NAME,
    LS_SF_DT_STRING,
    LS_SF_DT_TOKEN,
    LS_SF_DT_BYTESEQ,
    LS_SF_DT_BOOLEAN,
    LS_SF_DT_INNER_LIST_BEGIN,
    LS_SF_DT_INNER_LIST_END,
};


enum ls_sf_tlt
{   /* LS SF TLT: LiteSpeed Structured Field Top-Level Type */
    LS_SF_TLT_DICTIONARY,
    LS_SF_TLT_LIST,
    LS_SF_TLT_ITEM,
};


/* Return 0 if parsed correctly, -1 on error, -2 if ran out of memory. */
int
ls_sf_parse (
    /* Expected type of top-level input: */
    enum ls_sf_tlt,

    /* Input; does not have to be NUL-terminated: */
    const char *input, size_t input_sz,

    /* Callback function to call each time a token is parsed: */
    int (*)(void *user_data, enum ls_sf_dt, char *str),

    /* Additional data to pass to the callback: */
    void *user_data,

    /* Allocate memory from this memory buffer.  If set to NULL, regular
     * system memory allocator will be used.
     */
    char *mem_buf, size_t mem_buf_sz);



/* Convenience array with type names. */
extern const char *const ls_sf_dt2str[];


#endif
