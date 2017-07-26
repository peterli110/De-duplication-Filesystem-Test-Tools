#ifndef __POLICYFILE_LIB_H
#define __POLICYFILE_LIB_H

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#include <time.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/stat.h>

#define FILETYPE_MAX 1024
#define MAX_LINE 1024 + 12

enum filetype_mode {
  FILETYPE_NOTSET = 0,
  EFILETYPE_SET   = 1,
  IFILETYPE_SET   = 2
};

enum policy_validator {
  INVBRACE      = 1,         // braces not paired
  EFORMAT       = 2,         // format error, each parameter must be a new line
  PATHNOTSET    = 3,         // path not set
  INVPATH       = 4,         // path not existed or not a directory
  GLOBALNOTSET  = 5,         // global parameters not set
  ERANGEPATH    = 6,         // path is too long
  ERANGEEFT     = 7,         // efiletype is too long
  ERANGEIFT     = 8,         // ifiletype is too long
  FILETYPEERR   = 9,         // both efiletype and ifiletype are set
  EDISKUSAGE    = 10,        // disk usage is not 0 - 100
  EMINFS        = 11,        // minfilesize invalid
  EFILEAGE      = 12,        // fileage format error
  EEXCLUSIVE    = 13,        // both exclusive mode and other parameters are set
  INVPARAM      = 14,        // invalid or unknown parameters
  ECRLF         = 15         // file is saved with CRLF format(\r\n)
};

enum time_level {
  SECONDS       = 1,
  MINUTES       = 2,
  HOURS         = 3,
  DAYS          = 4
};

typedef struct policy {
  char path[PATH_MAX];
  char efiletype[FILETYPE_MAX];  // excluded file types
  char ifiletype[FILETYPE_MAX];  // included file types
  int diskusage;
  size_t minfilesize;          // megabytes
  time_t fileage;                // seconds
  bool exclusive;
  int filetype_setmode;      // only one of the filetype can be set
}DFSPolicy;

int policy_number();
long locate_policy(int num);
void generate_policy(DFSPolicy mypolicy);
DFSPolicy parse_policy(int num);
int validate_policy();


#endif
