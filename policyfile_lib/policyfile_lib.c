/* TODO:
        generate default policy
        clean up one/all policy
        modify one policy
*/
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
#include "policyfile_lib.h"

char *policypath="/tmp/dfspolicy";

void timet_to_days(time_t t, char fileage[256]) {
  int d = (t / 3600) / 24;       // days
  int h = (t / 3600) % 24;       // hours
  //int m = (t / 60) % 60;         // minutes(reserved)
  //int s = t % 60;                // seconds(reserved)
  if (h > 0 && d == 0) {
    sprintf(fileage, "fileage=%dhours \n", h);
  }
  if (h > 0 && d > 0) {
    sprintf(fileage, "fileage=%ddays %dhours \n", d, h);
  }
}

time_t days_to_timet(char fileage[MAX_LINE]) {
  time_t t;
  char *tm, *tmp;
  int d = 0, h = 0;
  int m = 0, s = 0;
  if (strstr(fileage, "fileage=") == NULL) {
    return -1;
  }
  tm = strtok_r(fileage, "=", &tmp);
  // tm = "xdays yhours"
  tm = strtok_r(NULL, "=", &tmp);
  if (strstr(tm, "days") != NULL) {
    // tm = "xdays"
    tm = strtok_r(tm, " ", &tmp);
    // delete "days"
    *(tm + strlen(tm) - 4) = '\0';
    d = atoi(tm);
    // tm = "yhours"
    tm = strtok_r(NULL, " ", &tmp);
  }
  if (strstr(tm, "hours") != NULL) {
    // delete "hours"
    *(tm + strlen(tm) - 5) = '\0';
    h = atoi(tm);
    // reserved for minutes/seconds
    tm = strtok_r(NULL, " ", &tmp);
  }
  t = (d * 24 * 3600) + (h * 3600) + (m * 60) + s;
  return t;
}

// verify a pair of braces and count the number
int policy_number() {
  int ch;
  int braces = 0;
  int verifybrace = 0;

  FILE *fp = NULL;
  fp = fopen(policypath, "r");
  if (fp != NULL) {
    while ((ch = fgetc(fp)) != EOF) {
      if (ch == '{') {
        braces++;
        verifybrace++;
      }
      if (ch == '}') {
        if (braces==0) {
          fclose(fp);
          return -1;
        }
        verifybrace--;
      }
    }

    if (verifybrace != 0) {
      fclose(fp);
      return -1;
    }
    else {
      fclose(fp);
      return braces;
    }
  }
  // file not exist
  else {
    return -2;
  }
}

long locate_policy(int num) {
  long offset = 0;
  int number = 1;
  char line[MAX_LINE];
  FILE *fp;

  if (num <= 0)
    return -EINVAL;

  fp = fopen(policypath, "r");
  if (fp == NULL)
    return -EEXIST;

  if (num == 1) {
    rewind(fp);
    offset = ftell(fp);
    fclose(fp);
    return offset;
  }

  if (num > policy_number()) {
    fclose(fp);
    return -ERANGE;
  }

  while (fgets(line, MAX_LINE, fp) != NULL) {
    if (strcmp(line, "}\n") == 0) {
      number++;
      if (num == number) {
        offset = ftell(fp);
      }
    }
  }
  fclose(fp);
  return offset;
}

void generate_policy(DFSPolicy mypolicy) {
  FILE *fp = NULL;
  char brace1[] = "{\n";
  char brace2[] = "}\n";
  char path[PATH_MAX+6];
  char diskusage[20];
  char efiletype[FILETYPE_MAX+12];
  char ifiletype[FILETYPE_MAX+12];
  char fileage[266];
  char minfilesize[128];
  char exclusive[] = "exclusive=yes\n";

  fp = fopen(policypath, "a");
  if (fp != NULL) {
    // {
    fwrite(brace1, strlen(brace1), 1, fp);

    // PATH
    sprintf(path, "path=%s\n", mypolicy.path);
    fwrite(path, strlen(path), 1, fp);

    if (mypolicy.exclusive != true) {
      // Disk usage
      sprintf(diskusage, "diskusage=%d%%\n", mypolicy.diskusage);
      fwrite(diskusage, strlen(diskusage), 1, fp);

      // File type
      switch (mypolicy.filetype_setmode) {
        case FILETYPE_NOTSET:
          break;
        case EFILETYPE_SET:
          sprintf(efiletype, "efiletype=%s\n", mypolicy.efiletype);
          fwrite(efiletype, strlen(efiletype), 1, fp);
          break;
        case IFILETYPE_SET:
          sprintf(ifiletype, "ifiletype=%s\n", mypolicy.ifiletype);
          fwrite(ifiletype, strlen(ifiletype), 1, fp);
          break;
      }

      // File age
      timet_to_days(mypolicy.fileage, fileage);
      fwrite(fileage, strlen(fileage), 1, fp);

      // Minimun file size
      sprintf(minfilesize, "minfilesize=%zuM\n", mypolicy.minfilesize);
      fwrite(minfilesize, strlen(minfilesize), 1, fp);
    }
    // Exclusive mode
    else {
      fwrite(exclusive, strlen(exclusive), 1, fp);
    }

    // }
    fwrite(brace2, strlen(brace2), 1, fp);
    fflush(fp);
    fclose(fp);
  }
  else {
    //report error
  }
}

DFSPolicy parse_policy(int num) {
  DFSPolicy thispolicy;
  int bracenum = 1;
  FILE *fp = NULL;
  char *tmp;
  char line[MAX_LINE];
  char *var;


  fp = fopen(policypath, "r");
  while (fgets(line, MAX_LINE, fp) != NULL) {
    if (strcmp(line, "{\n") == 0) {
      if (num == bracenum) {
        while (1) {
          fgets(line, MAX_LINE, fp);
          // path
          if (strstr(line, "path=") != NULL) {
            var = strtok_r(line, "=", &tmp);
            var = strtok_r(NULL, "=", &tmp);
            // delete the last '\n'
            *(var + strlen(var) - 1) = '\0';
            strncpy(thispolicy.path, var, strlen(var));
            //memset(&var, 0, sizeof(var));
          }
          // efiletype
          if (strstr(line, "efiletype=") != NULL) {
            var = strtok_r(line, "=", &tmp);
            var = strtok_r(NULL, "=", &tmp);
            *(var + strlen(var) - 1) = '\0';
            strncpy(thispolicy.efiletype, var, strlen(var));
            //memset(&var, 0, sizeof(var));
            thispolicy.filetype_setmode = EFILETYPE_SET;
          }
          // ifiletype
          else if (strstr(line, "ifiletype=") != NULL) {
            var = strtok_r(line, "=", &tmp);
            var = strtok_r(NULL, "=", &tmp);
            *(var + strlen(var) - 1) = '\0';
            strncpy(thispolicy.ifiletype, var, strlen(var));
            //memset(&var, 0, sizeof(var));
            thispolicy.filetype_setmode = IFILETYPE_SET;
          }
          else {
            thispolicy.filetype_setmode = FILETYPE_NOTSET;
          }
          // diskusage
          if (strstr(line, "diskusage=") != NULL) {
            var = strtok_r(line, "=", &tmp);
            var = strtok_r(NULL, "=", &tmp);
            // delete last "%\n"
            *(var + strlen(var) - 2) = '\0';
            int diskusage = atoi(var);
            thispolicy.diskusage = diskusage;
            //memset(&var, 0, sizeof(var));
          }
          // minfilesize
          if (strstr(line, "minfilesize=") != NULL) {
            var = strtok_r(line, "=", &tmp);
            var = strtok_r(NULL, "=", &tmp);
            char measurement = *(var + strlen(var) - 2);
            // delete last "M\n"
            *(var + strlen(var) - 2) = '\0';
            if (measurement == 'M' || measurement == 'm') {
              thispolicy.minfilesize = (ssize_t)atoi(var);
            }
            if (measurement == 'G' || measurement == 'g') {
              thispolicy.minfilesize = (ssize_t)(atoi(var) * 1024);
            }
            if (measurement == 'T' || measurement == 't') {
              thispolicy.minfilesize = (ssize_t)(atoi(var) * 1024 * 1024);
            }
            //memset(&var, 0, sizeof(var));
          }

          // fileage
          if (strstr(line, "fileage=") != NULL) {
            thispolicy.fileage = days_to_timet(line);
          }

          // exclusive
          if (strstr(line, "exclusive=yes") != NULL) {
            thispolicy.exclusive = true;
          }
          else {
            thispolicy.exclusive = false;
          }

          // }: break
          if (strcmp(line, "}\n") == 0) {
            break;
          }
        }
      }
      bracenum++;
    }
  }
  fclose(fp);
  return thispolicy;
}

int validate_policy() {
  int num = policy_number();
  if (num == -1) {
    return -INVBRACE;
  }
  if (num == -2) {
    return -EEXIST;
  }

  FILE *fp = NULL;
  char line[MAX_LINE];
  int i, p, timelevel, minfilesize;
  long offset;
  char *var, *value, *age, *agetmp, *tmp;
  bool expectedexclusive , efiletypeset, ifiletypeset;
  struct stat buf;
  fp = fopen(policypath, "r");

  // check CRLF
  while (fgets(line, MAX_LINE, fp) != NULL) {
    for (i = 0; line[i] != '\0'; i++) {
      if (line[i] == '\r'&& line[i+1] == '\n') {
        fclose(fp);
        return -ECRLF;
      }
    }
  }

  // check format:
  // every policy should begin with '{', end with '}'
  for (p = 1; p <= policy_number(); p++) {
    expectedexclusive = true;
    efiletypeset = false;
    ifiletypeset = false;
    offset = locate_policy(p);
    fseek(fp, offset, SEEK_SET);
    // first line must be '{'
    if (fgets(line, MAX_LINE, fp) != NULL && strcmp(line, "{\n") != 0) {
      fclose(fp);
      return -EFORMAT;
    }

    // first parameter of each policy must be "path"
    fseek(fp, offset, SEEK_SET);
    // skip '{'
    fgets(line, MAX_LINE, fp);
    fgets(line, MAX_LINE, fp);
    if (strlen(line) > 5) {
      line[5] = '\0';
      if (strcmp(line, "path=") != 0) {
        fclose(fp);
        return -PATHNOTSET;
      }
    }
    else {
      fclose(fp);
      return -PATHNOTSET;
    }

    // start from second line of each policy
    fseek(fp, offset, SEEK_SET);
    // skip '{'
    fgets(line, MAX_LINE, fp);
    bool newlinefound;
    int equalsignnum;
    while (fgets(line, MAX_LINE, fp) != NULL) {

      if (strchr(line, '}') != NULL) {
        if (strcmp(line, "}\n") != 0) {
          fclose(fp);
          return -EFORMAT;
        }
        else
          break;
      }
      newlinefound = false;
      equalsignnum = 0;
      // line[0] can't be '=', so start from line[1]
      // there must be "xxx=xxx" in each line, with a '\n' before '\0'
      // there must be only one equal sign in each line
      for (i = 1; line[i] != '\0'; i++) {
        if (line[i] == '=' && line[i+1] != '\n' && line[i+1] != '\0')
          equalsignnum++;
        if (line[i] == '\n' && line[i+1] == '\0')
          newlinefound = true;
      }
      if (equalsignnum != 1 || newlinefound == false) {
        printf("num:%d\n", equalsignnum);
        fclose(fp);
        return -EFORMAT;
      }

      // check other parameters
      // get parameter name
      var = strtok_r(line, "=", &tmp);
      // path
      if (strcmp(var, "path") == 0) {
        value = strtok_r(NULL, "=", &tmp);
        // delete the last '\n'
        *(value + strlen(value) - 1) = '\0';
        // path in first policy must be "global"
        if (p == 1 && strcmp(value, "global") != 0) {
          fclose(fp);
          return -GLOBALNOTSET;
        }
        // check the length of path
        if (strlen(value) > PATH_MAX) {
          fclose(fp);
          return -ERANGEPATH;
        }
        // check path is valid
        if (p > 1 && (stat(value, &buf) != 0 || !S_ISDIR(buf.st_mode))) {
          fclose(fp);
          return -INVPATH;
        }
        // TODO: check if path is not dfs partition
      }

      // diskusage
      if (strcmp(var, "diskusage") == 0) {
        value = strtok_r(NULL, "=", &tmp);
        // delete the last '\n'
        *(value + strlen(value) - 1) = '\0';
        if (*(value + strlen(value) - 1) == '%') {
          // delete '%'
          *(value + strlen(value) - 1) = '\0';
          int usage = atoi(value);
          if (usage > 100 || usage <= 0) {
            fclose(fp);
            return -EDISKUSAGE;
          }
          expectedexclusive = false;
        }
        else {
          fclose(fp);
          return -EDISKUSAGE;
        }
      }

      // efiletype
      if (strcmp(var, "efiletype") == 0) {
        efiletypeset = true;
        value = strtok_r(NULL, "=", &tmp);
        // delete the last '\n'
        *(value + strlen(value) - 1) = '\0';
        if (strlen(value) > FILETYPE_MAX) {
          fclose(fp);
          return -ERANGEEFT;
        }
        expectedexclusive = false;
      }

      // ifiletype
      if (strcmp(var, "ifiletype") == 0) {
        ifiletypeset = true;
        value = strtok_r(NULL, "=", &tmp);
        // delete the last '\n'
        *(value + strlen(value) - 1) = '\0';
        if (strlen(value) > FILETYPE_MAX) {
          fclose(fp);
          return -ERANGEEFT;
        }
        expectedexclusive = false;
      }

      if (efiletypeset && ifiletypeset) {
        fclose(fp);
        return -FILETYPEERR;
      }

      // minfilesize
      if (strcmp(var, "minfilesize") == 0) {
        value = strtok_r(NULL, "=", &tmp);
        // delete the last '\n'
        *(value + strlen(value) - 1) = '\0';
        // integer only
        if (strchr(value, '.') != NULL) {
          fclose(fp);
          return -EMINFS;
        }
        // minimum file size must be larger than 0
        minfilesize = atoi(value);
        if (minfilesize <= 0) {
          fclose(fp);
          return -EMINFS;
        }
        expectedexclusive = false;
      }

      // file age
      if (strcmp(var, "fileage") == 0) {
        value = strtok_r(NULL, "=", &tmp);
        // change the last '\n' to space
        *(value + strlen(value) - 1) = ' ';
        // check the first element
        age = strtok_r(value, " ", &agetmp);
        if (strstr(age, "days") != NULL) {
          timelevel = DAYS;
          while(*age != 'd') {
            if (!isdigit(*age++)) {
              fclose(fp);
              return -EFILEAGE;
            }
          }
        }
        if (strstr(age, "hours") != NULL) {
          timelevel = HOURS;
          while(*age != 'h') {
            if (!isdigit(*age++)) {
              fclose(fp);
              return -EFILEAGE;
            }
          }
        }
        if (strstr(age, "minutes") != NULL) {
          timelevel = MINUTES;
          while(*age != 'm') {
            if (!isdigit(*age++)) {
              fclose(fp);
              return -EFILEAGE;
            }
          }
        }
        if (strstr(age, "seconds") != NULL) {
          timelevel = SECONDS;
          while(*age != 's') {
            if (!isdigit(*age++)) {
              fclose(fp);
              return -EFILEAGE;
            }
          }
        }
        // check the rest elements
        while ((age = strtok_r(NULL, " ", &agetmp)) != NULL) {
          // must not be days
          if (strstr(age, "days") != NULL) {
            fclose(fp);
            return -EFILEAGE;
          }
          if (strstr(age, "hours") != NULL) {
            if (timelevel <= HOURS) {
              fclose(fp);
              return -EFILEAGE;
            }
            while(*age != 'h') {
              if (!isdigit(*age++)) {
                fclose(fp);
                return -EFILEAGE;
              }
            }
            timelevel = HOURS;
          }
          if (strstr(age, "minutes") != NULL) {
            if (timelevel <= MINUTES) {
              fclose(fp);
              return -EFILEAGE;
            }
            while(*age != 'm') {
              if (!isdigit(*age++)) {
                fclose(fp);
                return -EFILEAGE;
              }
            }
            timelevel = MINUTES;
          }
          if (strstr(age, "seconds") != NULL) {
            if (timelevel <= SECONDS) {
              fclose(fp);
              return -EFILEAGE;
            }
            while(*age != 's') {
              if (!isdigit(*age++)) {
                fclose(fp);
                return -EFILEAGE;
              }
            }
            timelevel = SECONDS;
          }

        }
        expectedexclusive = false;
      }
      // TODO: hours must less than 24, minutes and seconds must less than 60

      // exclusive
      if (strcmp(var, "exclusive") == 0) {
        value = strtok_r(NULL, "=", &tmp);
        // delete the last '\n'
        *(value + strlen(value) - 1) = '\0';
        // integer only
        if (strcmp(value, "yes") != 0) {
          fclose(fp);
          return -EEXCLUSIVE;
        }
        if (expectedexclusive == false) {
          fclose(fp);
          return -EEXCLUSIVE;
        }
      }

      // unknown parameter
      if (strcmp(var, "path") != 0 && strcmp(var, "efiletype") != 0 &&
      strcmp(var, "ifiletype") != 0 && strcmp(var, "diskusage") != 0 &&
      strcmp(var, "minfilesize") != 0 && strcmp(var, "fileage") != 0 &&
      strcmp(var, "exclusive") !=0) {
        fclose(fp);
        return -INVPARAM;
      }
    }
  }

  return 0;
}
