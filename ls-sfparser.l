%top{
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
}
%{
#include <stddef.h>
#include "ls-sfparser.h"
struct ls_sf_parser
{
    /* Return 0 on success, -1 on error to stop parsing. */
    int              (*callback)(void *user_data, enum ls_sf_dt,
                                            char *str, size_t len, int off);
    void              *user_data;
    const char        *errmsg;
    enum ls_sf_tlt     top_level_type;
    int                mem_failed;
    char              *mem;
    size_t             mem_sz;
    size_t             mem_off;
    /* XXX "last malloced" allows for a couple of rudimentary optimizations,
     * but they never occurred in the input I tried.
     */
    char              *last_malloced;
};
#define SFP ((struct ls_sf_parser *) yyextra)
#define CALLBACK(dt_, str_, len_, addl_) do {                       \
    if (SFP->callback(SFP->user_data, (dt_), (str_), (len_),        \
            (addl_) >= 0 ?                                          \
            yyg->yy_c_buf_p - yyleng - YY_CURRENT_BUFFER->yy_ch_buf + (addl_) :  \
            (addl_)))                                               \
        return -1;                                                  \
} while (0)
#define YY_FATAL_ERROR(msg_) do {                                   \
    (void) yy_fatal_error /* silence compiler warning */;           \
    ((struct ls_sf_parser *)                                        \
                (yyget_extra(yyscanner)))->errmsg = (msg_);         \
    ((struct yyguts_t*)yyscanner)->yy_start = 1 + 2 * ERROR_STATE;  \
} while (0)
%}

%option prefix="ls_sfp_"
%option noyywrap noinput nounput noyy_top_state
%option reentrant
%option batch
%option nounistd
%option nodefault
%option noyyrealloc noyyalloc noyyfree
%option never-interactive

DIGIT      [0-9]
SP         \x20
OWS        [\t\x20]
DOT        [.]
KEY        [[:lower:]*][[:lower:][:digit:]*_.-]*
INTEGER    -?{DIGIT}{1,15}
DECIMAL    -?{DIGIT}{1,12}{DOT}{DIGIT}{1,3}
UNESCAPED  \x20|\x21|[\x23-\x5B]|[\x5D-\x7E]
ESCAPED    \\[\\"]
CHR        {UNESCAPED}|{ESCAPED}
DQUOTE     ["]
/* TCHAR: RFC 7230, Section 3.2.6 */
TCHAR      [[:digit:][:alpha:]:/!#$%&'*+.^_`|~-]
TOKEN      [[:alpha:]*]{TCHAR}*
BASE64     [[:alpha:][:digit:]/=+]
COLON      [:]
BOOLEAN    \?[01]

%x DICTIONARY DIC_MEMBER_EQ DIC_MEMBER_ITEM DIC_NEXT_ITEM
%x DIC_OPTIONAL_PARAM DIC_PARAM_EQ DIC_PARAM_KEY DIC_PARAM_ITEM

%x LIST_OPTIONAL_PARAM LIST LIST_NEXT_ITEM LIST_PARAM_KEY LIST_PARAM_ITEM
%x LIST_PARAM_EQ

%x ITEM ITEM_OPTIONAL_PARAM ITEM_PARAM_EQ ITEM_PARAM_KEY ITEM_BARE_ITEM

%x INNER_LIST IL_OPTIONAL_PARAM IL_PARAM_KEY IL_PARAM_EQ IL_PARAM_ITEM

%x ERROR_STATE

%%

    char TRUE[] = "1";

    switch (SFP->top_level_type)
    {
    case LS_SF_TLT_DICTIONARY:
        BEGIN(DICTIONARY);
        break;
    case LS_SF_TLT_LIST:
        BEGIN(LIST);
        break;
    case LS_SF_TLT_ITEM:
        BEGIN(ITEM);
        break;
    default:
        SFP->errmsg = "invalid top-level type specified";
        return -1;
    }

<DICTIONARY>{
    {SP}+                           /* Eat up whitespace */
    {KEY}                           { CALLBACK(LS_SF_DT_NAME, yytext, yyleng, 0);
                                      BEGIN(DIC_MEMBER_EQ); }
}

<DIC_NEXT_ITEM>{
    <<EOF>>                         { return -1; }
    {OWS}+                          /* Eat up whitespace */
    {KEY}                           { CALLBACK(LS_SF_DT_NAME, yytext, yyleng, 0);
                                      BEGIN(DIC_MEMBER_EQ); }
}

<DIC_MEMBER_EQ>=\({SP}*             { CALLBACK(LS_SF_DT_INNER_LIST_BEGIN, yytext + 1, yyleng - 1, 1);
                                      BEGIN(INNER_LIST); }

<DIC_MEMBER_EQ>=                    { BEGIN(DIC_MEMBER_ITEM); }

<DIC_MEMBER_EQ>{SP}*;               { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(DIC_PARAM_KEY); }

<DIC_MEMBER_EQ>{OWS}*,{OWS}*        { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(DIC_NEXT_ITEM); }

<DIC_MEMBER_EQ><<EOF>>              { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      return 0; }

<INNER_LIST>{
    \)                              { CALLBACK(LS_SF_DT_INNER_LIST_END, yytext, yyleng, 0);
                                      if (SFP->top_level_type == LS_SF_TLT_DICTIONARY)
                                          BEGIN(DIC_OPTIONAL_PARAM);
                                      else
                                          BEGIN(LIST_OPTIONAL_PARAM); }
    {INTEGER}                       { CALLBACK(LS_SF_DT_INTEGER, yytext, yyleng, 0);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {DECIMAL}                       { CALLBACK(LS_SF_DT_DECIMAL, yytext, yyleng, 0);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {DQUOTE}{CHR}*{DQUOTE}          {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_STRING, yytext + 1, yyleng - 2, 1);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {TOKEN}                         { CALLBACK(LS_SF_DT_TOKEN, yytext, yyleng, 0);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {COLON}{BASE64}*{COLON}         {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_BYTESEQ, yytext + 1, yyleng - 2, 1);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {BOOLEAN}                       { CALLBACK(LS_SF_DT_BOOLEAN, yytext + 1, yyleng - 1, 1);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    <<EOF>>                         { return -1; }
}

<IL_OPTIONAL_PARAM>{
    {SP}*;{SP}*                     { BEGIN(IL_PARAM_KEY); }
    \)                              { CALLBACK(LS_SF_DT_INNER_LIST_END, yytext, yyleng, 0);
                                      if (SFP->top_level_type == LS_SF_TLT_DICTIONARY)
                                          BEGIN(DIC_OPTIONAL_PARAM);
                                      else
                                          BEGIN(LIST_OPTIONAL_PARAM); }
    {SP}+                           { BEGIN(INNER_LIST); }
    <<EOF>>                         { return -1; }
}

<IL_PARAM_KEY>{KEY}                 { CALLBACK(LS_SF_DT_PARAM_NAME, yytext, yyleng, 0);
                                        BEGIN(IL_PARAM_EQ); }

<IL_PARAM_EQ>{
    =                               { BEGIN(IL_PARAM_ITEM); }
    {SP}+                           { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(IL_OPTIONAL_PARAM); }
    ;                               { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(IL_PARAM_KEY); }
    \)                              { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      CALLBACK(LS_SF_DT_INNER_LIST_END, yytext, yyleng, 0);
                                      if (SFP->top_level_type == LS_SF_TLT_DICTIONARY)
                                          BEGIN(DIC_OPTIONAL_PARAM);
                                      else
                                          BEGIN(LIST_OPTIONAL_PARAM); }
}

<IL_PARAM_ITEM>{
    {INTEGER}                       { CALLBACK(LS_SF_DT_INTEGER, yytext, yyleng, 0);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {DECIMAL}                       { CALLBACK(LS_SF_DT_DECIMAL, yytext, yyleng, 0);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {DQUOTE}{CHR}*{DQUOTE}          {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_STRING, yytext + 1, yyleng - 2, 1);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {TOKEN}                         { CALLBACK(LS_SF_DT_TOKEN, yytext, yyleng, 0);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {COLON}{BASE64}*{COLON}         {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_BYTESEQ, yytext + 1, yyleng - 2, 1);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    {BOOLEAN}                       { CALLBACK(LS_SF_DT_BOOLEAN, yytext + 1, yyleng - 1, 1);
                                      BEGIN(IL_OPTIONAL_PARAM);
                                    }
    <<EOF>>                         { return -1; }
}

<DIC_MEMBER_ITEM>{
    {INTEGER}                       { CALLBACK(LS_SF_DT_INTEGER, yytext, yyleng, 0);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {DECIMAL}                       { CALLBACK(LS_SF_DT_DECIMAL, yytext, yyleng, 0);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {DQUOTE}{CHR}*{DQUOTE}          {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_STRING, yytext + 1, yyleng - 2, 1);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {TOKEN}                         { CALLBACK(LS_SF_DT_TOKEN, yytext, yyleng, 0);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {COLON}{BASE64}*{COLON}         {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_BYTESEQ, yytext + 1, yyleng - 2, 1);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {BOOLEAN}                       { CALLBACK(LS_SF_DT_BOOLEAN, yytext + 1, yyleng - 1, 1);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    <<EOF>>                         { return -1; }
}

<DIC_OPTIONAL_PARAM>{
    {OWS}+;                         { return -1; }
    {OWS}+                          /* Eat up whitespace */
    ;{SP}*                          { BEGIN(DIC_PARAM_KEY); }
    ,                               { BEGIN(DIC_NEXT_ITEM); }
    <<EOF>>                         { return 0; }
}

<DIC_PARAM_KEY>{
    {SP}+                           /* Eat up whitespace */
    {KEY}                           { CALLBACK(LS_SF_DT_PARAM_NAME, yytext, yyleng, 0);
                                        BEGIN(DIC_PARAM_EQ); }
}

<DIC_PARAM_EQ>{
    =                               { BEGIN(DIC_PARAM_ITEM); }
    ,                               { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(DIC_NEXT_ITEM);
                                    }
    ;                               { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(DIC_PARAM_KEY);
                                    }
    {SP}+                           { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    <<EOF>>                         { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      return 0;
                                    }
}

<DIC_PARAM_ITEM>{
    {INTEGER}                       { CALLBACK(LS_SF_DT_INTEGER, yytext, yyleng, 0);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {DECIMAL}                       { CALLBACK(LS_SF_DT_DECIMAL, yytext, yyleng, 0);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {DQUOTE}{CHR}*{DQUOTE}          {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_STRING, yytext + 1, yyleng - 2, 1);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {TOKEN}                         { CALLBACK(LS_SF_DT_TOKEN, yytext, yyleng, 0);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {COLON}{BASE64}*{COLON}         {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_BYTESEQ, yytext + 1, yyleng - 2, 1);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    {BOOLEAN}                       { CALLBACK(LS_SF_DT_BOOLEAN, yytext + 1, yyleng - 1, 1);
                                      BEGIN(DIC_OPTIONAL_PARAM);
                                    }
    <<EOF>>                         { return -1; }
}

<LIST>{
    {OWS}+                          /* Eat up whitespace */
    ,                               { return -1; }
    .                               { yyless(0); BEGIN(LIST_NEXT_ITEM); }
}

<LIST_NEXT_ITEM>{
    <<EOF>>                         { return -1; }
    {OWS}+                          /* Eat up whitespace */
    \({SP}*                         { CALLBACK(LS_SF_DT_INNER_LIST_BEGIN, yytext, yyleng, 0);
                                      BEGIN(INNER_LIST); }
    {INTEGER}                       { CALLBACK(LS_SF_DT_INTEGER, yytext, yyleng, 0);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {DECIMAL}                       { CALLBACK(LS_SF_DT_DECIMAL, yytext, yyleng, 0);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {DQUOTE}{CHR}*{DQUOTE}          {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_STRING, yytext + 1, yyleng - 2, 1);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {TOKEN}                         { CALLBACK(LS_SF_DT_TOKEN, yytext, yyleng, 0);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {COLON}{BASE64}*{COLON}         {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_BYTESEQ, yytext + 1, yyleng - 2, 1);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {BOOLEAN}                       { CALLBACK(LS_SF_DT_BOOLEAN, yytext + 1, yyleng - 1, 1);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
}

<LIST_OPTIONAL_PARAM>{
    {OWS}+;                         { return -1; }
    {OWS}+                          /* Eat up whitespace */
    ;{SP}*                          { BEGIN(LIST_PARAM_KEY); }
    ,                               { BEGIN(LIST_NEXT_ITEM); }
}

<LIST_PARAM_KEY>{KEY}               { CALLBACK(LS_SF_DT_PARAM_NAME, yytext, yyleng, 0);
                                        BEGIN(LIST_PARAM_EQ); }

<LIST_PARAM_EQ>{
    =                               { BEGIN(LIST_PARAM_ITEM); }
    {SP}+                           { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(LIST_OPTIONAL_PARAM); }
    ;                               { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(LIST_PARAM_KEY); }
    ,                               { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(LIST_NEXT_ITEM); }
}

<LIST_PARAM_ITEM>{
    {INTEGER}                       { CALLBACK(LS_SF_DT_INTEGER, yytext, yyleng, 0);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {DECIMAL}                       { CALLBACK(LS_SF_DT_DECIMAL, yytext, yyleng, 0);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {DQUOTE}{CHR}*{DQUOTE}          {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_STRING, yytext + 1, yyleng - 2, 1);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {TOKEN}                         { CALLBACK(LS_SF_DT_TOKEN, yytext, yyleng, 0);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {COLON}{BASE64}*{COLON}         {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_BYTESEQ, yytext + 1, yyleng - 2, 1);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
    {BOOLEAN}                       { CALLBACK(LS_SF_DT_BOOLEAN, yytext + 1, yyleng - 1, 1);
                                      BEGIN(LIST_OPTIONAL_PARAM);
                                    }
}

<ITEM>{
    {SP}+                           /* Eat up whitespace */
    {INTEGER}                       { CALLBACK(LS_SF_DT_INTEGER, yytext, yyleng, 0);
                                      BEGIN(ITEM_OPTIONAL_PARAM);
                                    }
    {DECIMAL}                       { CALLBACK(LS_SF_DT_DECIMAL, yytext, yyleng, 0);
                                      BEGIN(ITEM_OPTIONAL_PARAM);
                                    }
    {DQUOTE}{CHR}*{DQUOTE}          {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_STRING, yytext + 1, yyleng - 2, 1);
                                      BEGIN(ITEM_OPTIONAL_PARAM);
                                    }
    {TOKEN}                         { CALLBACK(LS_SF_DT_TOKEN, yytext, yyleng, 0);
                                      BEGIN(ITEM_OPTIONAL_PARAM);
                                    }
    {COLON}{BASE64}*{COLON}         {
                                      yytext[yyleng - 1] = '\0';
                                      CALLBACK(LS_SF_DT_BYTESEQ, yytext + 1, yyleng - 2, 1);
                                      BEGIN(ITEM_OPTIONAL_PARAM);
                                    }
    {BOOLEAN}                       { CALLBACK(LS_SF_DT_BOOLEAN, yytext + 1, yyleng - 1, 1);
                                      BEGIN(ITEM_OPTIONAL_PARAM);
                                    }
    <<EOF>>                         { return -1; }
}

<ITEM_OPTIONAL_PARAM>{
    {SP}+                           /* Eat up whitespace */
    ;{SP}*                          { BEGIN(ITEM_PARAM_KEY); }
}

<ITEM_PARAM_KEY>{
    {SP}+                           /* Eat up whitespace */
    {KEY}                           { CALLBACK(LS_SF_DT_PARAM_NAME, yytext, yyleng, 0);
                                        BEGIN(ITEM_PARAM_EQ); }
}

<ITEM_PARAM_EQ>{
    =                               { BEGIN(ITEM); }
    {SP}+                           { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(ITEM_OPTIONAL_PARAM);
                                    }
    ;                               { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      BEGIN(ITEM_PARAM_KEY);
                                    }
    <<EOF>>                         { TRUE[0] = '1';
                                      CALLBACK(LS_SF_DT_BOOLEAN, TRUE, 1, -1);
                                      return 0;
                                    }
}

<ERROR_STATE>.                      { return -1; }

%%

const char *const ls_sf_dt2str[] =
{
    [LS_SF_DT_INTEGER]      = "INTEGER",
    [LS_SF_DT_DECIMAL]      = "DECIMAL",
    [LS_SF_DT_NAME]         = "NAME",
    [LS_SF_DT_PARAM_NAME]   = "PARAM_NAME",
    [LS_SF_DT_STRING]       = "STRING",
    [LS_SF_DT_TOKEN]        = "TOKEN",
    [LS_SF_DT_BYTESEQ]      = "BYTESEQ",
    [LS_SF_DT_BOOLEAN]      = "BOOLEAN",
    [LS_SF_DT_INNER_LIST_BEGIN] = "INNER_LIST_BEGIN",
    [LS_SF_DT_INNER_LIST_END] = "INNER_LIST_END",
};


int
ls_sf_parse (enum ls_sf_tlt top_level_type, const char *input, size_t input_sz,
    int (*callback)(void *user_data, enum ls_sf_dt, char *str, size_t, int),
    void *user_data, char *mem_buf, size_t mem_buf_sz)
{
    struct ls_sf_parser parser;
    yyscan_t scanner;
    YY_BUFFER_STATE buf;
    int ret;

    parser.top_level_type = top_level_type;
    parser.callback = callback;
    parser.user_data = user_data;
    parser.errmsg = NULL;
    parser.mem_failed = 0;

    if (mem_buf && mem_buf_sz)
    {
        parser.mem = mem_buf;
        parser.mem_off = 0;
        parser.mem_sz = mem_buf_sz;
        parser.last_malloced = NULL;
    }
    else
        parser.mem = NULL;

    if (0 != ls_sfp_lex_init_extra(&parser, &scanner))
        return -1;

    buf = ls_sfp__scan_bytes(input, input_sz, scanner);
    if (buf)
    {
        ret = ls_sfp_lex(scanner);
        if (parser.mem_failed)
            ret = -2;
        else if (parser.errmsg)
            ret = -1;
        ls_sfp__delete_buffer(buf, scanner);
    }
    else
        ret = -2;

    ls_sfp_lex_destroy(scanner);
    return ret;
}


void *
ls_sfp_alloc (size_t bytes, void *yyscanner)
{
    struct ls_sf_parser *const parser = yyget_extra(yyscanner);

    if (parser->mem)
    {
        if (bytes + parser->mem_off < parser->mem_sz)
        {
            parser->last_malloced = parser->mem + parser->mem_off;
            parser->mem_off += bytes;
            return parser->last_malloced;
        }
        else
        {
            parser->mem_failed = 1;
            return NULL;
        }
    }
    else
        return malloc(bytes);
}


#define MAX(a, b) ((a) > (b) ? (a) : (b))

void *
ls_sfp_realloc (void *ptr, size_t bytes, void *yyscanner)
{
    struct ls_sf_parser *const parser = yyget_extra(yyscanner);
    void *ret;

    if (parser->mem)
    {
        if ((char *) ptr == parser->last_malloced)
        {
            if (parser->last_malloced + bytes <= parser->mem + parser->mem_sz)
                return ptr;
            else
            {
                parser->mem_failed = 1;
                return NULL;
            }
        }
        else if (ret = ls_sfp_alloc(bytes, yyscanner), ret != NULL)
        {
            memcpy(ret, ptr,
                /* We don't know how large it was, so just copy the max */
                MAX(bytes, (size_t) (
                                parser->mem + parser->mem_sz - (char *) ptr)));
            return ret;
        }
        else
        {
            parser->mem_failed = 1;
            return NULL;
        }
    }
    else
        return realloc(ptr, bytes);
}


void
ls_sfp_free (void *ptr, void *yyscanner)
{
    struct ls_sf_parser *const parser = yyget_extra(yyscanner);

    if (parser->mem)
    {
        if ((char *) ptr == parser->last_malloced)
            parser->mem_off = parser->last_malloced - parser->mem;
    }
    else
        free(ptr);
}
