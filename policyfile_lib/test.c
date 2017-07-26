#include "policyfile_lib.h"

int main(int argc, char *argv[]) {
/*
  DFSPolicy thispolicy;
  strcpy(thispolicy.path, "/mnt/dfs");
  strcpy(thispolicy.efiletype, "txt,mp4,avi");
  thispolicy.diskusage = 50;
  thispolicy.minfilesize = 15;
  thispolicy.fileage = 3600 * 24 + 3600;
  thispolicy.exclusive = false;
  thispolicy.filetype_setmode = EFILETYPE_SET;
  generate_policy(thispolicy);
*/
  int rc = policy_number();
  printf("total number: %d\n", rc);

  DFSPolicy a = parse_policy(1);
  printf("path: %s\n", a.path);
  printf("efiletype: %s\n", a.efiletype);
  printf("age: %ld\n", a.fileage);

  rc = validate_policy();
  printf("rc of validate_policy = %d\n", rc);


  return 0;
}
