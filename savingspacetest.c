#include <sys/types.h>
#include <sys/stat.h>
#ifndef linux
# include <sys/dirent.h>
#endif
#include <sys/file.h>
#include <sys/mman.h>
#include <limits.h>
#include <err.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <errno.h>
#include <time.h>

# define MEGABYTES 1024 * 1024

int fd;
int cur_offset;
char temp_buf[MEGABYTES];
char dup_buf[MEGABYTES];
char fname[]="/mnt/dfs/tf";
int nMBgenerated = 0;
int nMBduplicated = 0;
int duplicated = 0;
int generated = 0;
int file_number = 0;
int repo = 0;
int savedspace = 0;
int rand_duplicate = 10; //duplicated size = rand()%rand_duplicate + 1;
int rand_generate = 20;//generated size = rand()%rand_generate + duplicated +1;
int testcalls = 0;
int	sig;


void reformat(void)
{
	printf("Reformat dfs partition...\n");
	char format[1024] = "REFORMAT=yes ./sanity.sh start";
	system(format);
	printf("\nREFORMAT completed, start testing...\n\n");
}

//use system() to call dfs_cli
void dodedup(char *fname)
{

	char dedup_file[1024] = "../cmd/dfs_cli dedup ";
	strncat(dedup_file, fname, strlen(fname));
	printf("deduping...%s\n",dedup_file);
	int ret = system(dedup_file);
	if (ret != 0){
		printf("dedup error\n");
	}

}

//check the output of "dfs_cli check"
int docheck(char *fname)
{

	char check_file[1024] = "../cmd/dfs_cli check ";
	strncat(check_file, fname, strlen(fname));
	FILE *fp;
	char buffer[1024];
	fp=popen(check_file, "r");
	fgets(buffer, sizeof(buffer), fp);
	pclose(fp);

	if (strstr(buffer, "deduped") == NULL)
		return 0; //not deduped
	return 1; //deduped
}

int blocks_used_in_repo(void)
{

	char command[1024] =
		"../cmd/dfs_cli list -v | awk -F 'First available block:' 'BEGIN{sum=0} {sum+=$2} END{print sum}'";
	FILE *fp;
	char buffer[1024];
	int blocks;
	char *ret;
	errno = 0;

	fp=popen(command, "r");
	if (fp == NULL) {
		fprintf(stderr, "popen error:  %s\n", strerror(errno));
		exit(-1);
	}
	ret = fgets(buffer, sizeof(buffer), fp);
	if(ret == NULL){
		fprintf(stderr, "fgets error:  %s\n", strerror(errno));
		exit(-1);
	}
	if (pclose(fp) == -1) {
		fprintf(stderr, "pclose error:  %s\n", strerror(errno));
		exit(-1);
	}

	blocks = strtol(buffer, NULL, 10);
	if ((errno == ERANGE && (blocks == LONG_MAX || blocks == LONG_MIN))
				 || (errno != 0 && blocks == 0)) {
					 fprintf(stderr, "strtol error:  %s\n", strerror(errno));
					 exit(-1);
 }
	return blocks;
}

//generate 1MB random data
const char* gen1mbdata(char *s)
{
	int i;
	int ret;
	for(i=0; i<MEGABYTES; i++){
		ret = sprintf(temp_buf+i, "%d", rand()%10);
		if(ret != 1){
			printf("sprintf error\n");
			exit(-1);
		}
	}
	return s;
}

//generate n MB data into test file
//d MB of them in a random position which is aligned to 1MB are duplicated
void genrandomdata(char *fname, int n, int d)
{
	int ret, ret2, i, k = 0;

	if (d > n){
		printf("Duplicated %dMB must be smaller than the random data %dMB\n", d, n);
		exit(-1);
	}

	fd = open(fname, O_RDWR|O_CREAT, 0666);
  if (fd < 0) {
    fprintf(stderr, "open error:  %s\n", strerror(errno));
    exit(-1);
  }

	for(i=0; i<n; i++){
		ret = write(fd, gen1mbdata(temp_buf), MEGABYTES);
		if (ret != MEGABYTES){
			if (ret == -1){
				fprintf(stderr, "write error:  %s\n", strerror(errno));
				exit(-1);
			}
			else
				printf("only %x bytes written\n", ret);
			exit(-1);
		}
	}

	ret2 = lseek(fd, (off_t)((rand()%(n-d))*MEGABYTES), SEEK_SET);
	if (ret2 == (off_t)-1){
		fprintf(stderr, "lseek error:  %s\n", strerror(errno));
		exit(-1);
	}

	for(k=0; k<d; k++){
		ret = write(fd, dup_buf, MEGABYTES);
		if (ret != MEGABYTES){
			if (ret == -1){
				fprintf(stderr, "write error:  %s\n", strerror(errno));
				exit(-1);
			}
			else
				printf("only %x bytes written\n", ret);
			exit(-1);
		}
	}
	if (close(fd)) {
		fprintf(stderr, "close error:  %s\n", strerror(errno));
		exit(-1);
	}
}

/*
	this test is to calculate accumulative size of file,
	and the duplicated part to get the estimated size used
	in repo, and compare with the output of dfs_cli list -v.
	All the duplicated data should use 1MB in repo.
*/
//blocks/256 will be the megabytes used in repo.
void test(char *fname)
{
	int repo_newfile, savedspace_newfile;
	duplicated = rand()%rand_duplicate + 1;
	generated = rand()%rand_generate + duplicated +1;

	nMBgenerated += generated;
	nMBduplicated +=duplicated;
	repo = nMBgenerated - nMBduplicated + 1;
	savedspace = nMBduplicated -1;

	genrandomdata(fname, generated, duplicated);
	dodedup(fname);

	if(!docheck(fname)){
		printf("dedup %s failed\n",fname);
		exit(-1);
	}

	if(repo == blocks_used_in_repo()/256){
		printf("%s deduped, file size: %d MB, duplicated size: %d MB\n\
All files: file size: %d MB, duplicated size: %d MB\n\
Data in repo: %d MB, space saved: %dMB\n\n", fname, generated, duplicated, \
		nMBgenerated, nMBduplicated, repo, savedspace);
	}
	else{
		printf("Data in repo %d MB mismatch with dfs_cli list -v %d MB\n"
		, repo, blocks_used_in_repo()/256);
		exit(-1);
	}
	testcalls++;
}

void cleanup(sig)
{
	if (sig)
		printf("signal %d\n", sig);
	printf("testcalls = %lu\n", testcalls);
	exit(sig);
}

void usage(void)
{
	fprintf(stdout, "usage: %s",
		"savingspacetest [-n number] [-g size] [-d size] [-h] \n\
	-h: help\n\
	-n number: total files to generate (default 0=infinite)\n\
	-d size: random duplications in each file from 1 to size MB (default 10)\n\
	-g size: random size of data in each file from 1 to size MB (default 20)\n\
	Notice: maxmum size of a single file will be g+d MB\n");
	exit(90);
}

int main(int argc, char **argv)
{
	int ret, ch;
	int i=0, n=0;
	errno = 0;

	srand(time(NULL));

	ret = sprintf(dup_buf, "%s", gen1mbdata(temp_buf));
	if(ret != MEGABYTES){
		printf("sprintf error\n");
		exit(-1);
	}

	while ((ch = getopt(argc, argv, "n:d:g:h"))
	       != EOF){
		switch (ch) {
		case 'n':
			n = strtol(optarg, NULL, 10);
			if ((errno == ERANGE && (n == LONG_MAX || n == LONG_MIN))
						 || (errno != 0 && n == 0)) {
							 fprintf(stderr, "strtol error:  %s\n", strerror(errno));
							 exit(-1);
		 }
			if (n < 0)
				usage();
			break;
		case 'd':
			rand_duplicate = strtol(optarg, NULL, 10);
			if ((errno == ERANGE && (rand_duplicate == LONG_MAX || rand_duplicate == LONG_MIN))
						 || (errno != 0 && rand_duplicate == 0)) {
							 fprintf(stderr, "strtol error:  %s\n", strerror(errno));
							 exit(-1);
		 }
			if (rand_duplicate < 0)
				usage();
			break;
		case 'g':
			rand_generate = strtol(optarg, NULL, 10);
			if ((errno == ERANGE && (rand_generate == LONG_MAX || rand_generate == LONG_MIN))
						 || (errno != 0 && rand_generate == 0)) {
							 fprintf(stderr, "strtol error:  %s\n", strerror(errno));
							 exit(-1);
		 }
			if (rand_generate < 0)
				usage();
			break;
		case 'h':
			usage();
			break;

		default:
			usage();
			break;
		}
	}

	signal(SIGHUP,	cleanup);
	signal(SIGINT,	cleanup);
	signal(SIGPIPE,	cleanup);
	signal(SIGALRM,	cleanup);
	signal(SIGTERM,	cleanup);
	signal(SIGXCPU,	cleanup);
	signal(SIGXFSZ,	cleanup);
	signal(SIGVTALRM,	cleanup);
	signal(SIGUSR1,	cleanup);
	signal(SIGUSR2,	cleanup);

	reformat();
	if (n == 0){
		while(++i){
			char filename[1024];
			char number[512];
			ret = sprintf(filename, "%s", fname);
			if(ret != strlen(fname)){
				printf("sprintf error\n");
				exit(-1);
			}
			ret = sprintf(number, "%d", i);
			if(ret < 0){
				printf("sprintf error\n");
				exit(-1);
			}
			strncat(filename, number, strlen(number));
			test(filename);
		}
	}
	else{
		while(i++ < n){
			char filename[1024];
			char number[512];
			ret = sprintf(filename, "%s", fname);
			if(ret != strlen(fname)){
				printf("sprintf error\n");
				exit(-1);
			}
			ret = sprintf(number, "%d", i);
			if(ret < 0){
				printf("sprintf error\n");
				exit(-1);
			}
			strncat(filename, number, strlen(number));
			test(filename);
		}
	}



  return 0;

}
