/* Parse HTTP/3 Priority Parameters
 *
 * See
 *  https://tools.ietf.org/html/draft-ietf-httpbis-priority-01
 */

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ls-sfparser.h"


struct prio {
    enum {
        URG_SET  = 1 << 0,  /* True if `urgency' is set */
        INC_SET  = 1 << 1,  /* True if `incremental' is set */
        URG_NAME = 1 << 2,  /* True if previous element dictionary name "u" */
        INC_NAME = 1 << 3,  /* True if previous element dictionary name "i" */
    }           flags;
    unsigned    urgency;
    bool        incremental;
};


static int
callback (void *user_data, enum ls_sf_dt type, char *str, size_t len, int off)
{
    struct prio *const prio = user_data;

    if (type == LS_SF_DT_NAME)
    {
        if (1 == len)
            switch (str[0])
            {
                case 'u': prio->flags |= URG_NAME; return 0;
                case 'i': prio->flags |= INC_NAME; return 0;
            }
    }
    else if (prio->flags & URG_NAME)
    {
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
        }
        else
        {
            printf("invalid type of urgency: %s\n", ls_sf_dt2str[type]);
            return -1;
        }
    }
    else if (prio->flags & INC_NAME)
    {
        if (type == LS_SF_DT_BOOLEAN)
        {
            prio->flags |= INC_SET;
            prio->incremental = str[0] - '0';
        }
        else
        {
            printf("invalid type of incremental: %s\n", ls_sf_dt2str[type]);
            return -1;
        }
    }
    prio->flags &= ~(INC_NAME|URG_NAME);

    return 0;
}


int
main (int argc, char **argv)
{
    struct prio prio;
    int ret;

    if (argc != 2)
    {
        printf("Usage: %s 'HTTP/3 priority parameters'\n", argv[0]);
        return 1;
    }

    memset(&prio, 0, sizeof(prio));
    ret = ls_sf_parse(LS_SF_TLT_DICTIONARY, argv[1], strlen(argv[1]), callback,
                                                &prio, NULL, 0);
    if (ret == 0)
    {
        printf("parsing successful\n");
        if (prio.flags & URG_SET)
            printf("urgency: %u\n", prio.urgency);
        else
            printf("urgency: <not set>\n");
        if (prio.flags & INC_SET)
            printf("incremental: %i\n", (int) prio.incremental);
        else
            printf("incremental: <not set>\n");
    }
    else
        printf("parsing failed\n");

    return ret ? -1 : 0;
}
