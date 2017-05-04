#include <sys/types.h>
#include <sys/stat.h>
#ifdef _UWIN
# include <sys/param.h>
# include <limits.h>
# include <time.h>
# include <strings.h>
# define MAP_FILE 0
#else
#ifndef linux
# include <sys/dirent.h>
#endif
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

int fd;
int cur_offset;
char fname[]="/mnt/dfs/tf1";
char buffer[]="abcdefghijklmn";

void close_file(void)
{
	cur_offset = lseek(fd, 0, SEEK_CUR);
	if (close(fd)) {
		fprintf(stderr, "close error:  %s\n", strerror(errno));
		exit(-1);
	}
	printf("file closed\n");
}

void open_file(void)
{
	fd = open(fname, O_RDWR|O_CREAT, 0666);
	printf("file opened, fd is %d\n", fd);
	if (fd < 0) {
		fprintf(stderr, "open error:  %s\n", strerror(errno));
		exit(-1);
	}
	int ret1 = lseek(fd, cur_offset, SEEK_SET);
	if(ret1 == -1){
		fprintf(stderr, "lseek error:  %s\n", strerror(errno));
		exit(-1);
	}
}

void dodedup(char *fname)//use system() to call dfs_cli
{
	close_file();

	char dedup_file[1024] = "../cmd/dfs_cli dedup ";
	strcat(dedup_file, fname);
	printf("deduping...\n");
	int ret = system(dedup_file);
	if (ret != 0){
		printf("dedup error\n");
	}

	open_file();
}

void dorestore(char *fname)//use system() to call dfs_cli
{
	close_file();

	char restore_file[1024] = "../cmd/dfs_cli restore ";
	strcat(restore_file, fname);
	printf("restoring...\n");
	int ret = system(restore_file);
	if (ret != 0){
		printf("restore error\n");
	}

	open_file();
}

int docheck(char *fname)//check the output of "dfs_cli check"
{
	close_file();

	char check_file[1024] = "../cmd/dfs_cli check ";
	strcat(check_file, fname);
	FILE *fp;
	char buffer[1024];
	fp=popen(check_file, "r");
	fgets(buffer, sizeof(buffer), fp);
	pclose(fp);

	open_file();

	if (strstr(buffer, "deduped") == NULL)
		return 0; //not deduped
	return 1; //deduped

}

void test(char *fname, int fd)
{
	if(!docheck(fname)) //if not deduped, dedup this file
		dodedup(fname);

	int ret = write(fd, buffer, sizeof(buffer));
	if(ret != sizeof(buffer)){
		fprintf(stderr, "write error:  %s\n", strerror(errno));
		exit(-1);
	}

	int ret1 = lseek(fd, 0, SEEK_CUR);
	printf("current offset is:%d\n", ret1);
	if(ret1 == -1){
		fprintf(stderr, "lseek error:  %s\n", strerror(errno));
		exit(-1);
	}

	if(!docheck(fname)){// not deduped
		printf("auto restore triggered\n");
		printf("ret: %d\n", ret);
	}

	if(docheck(fname))// deduped
		printf("auto restore failed\n");

}

int main()
{
	//	int ret = dodedup(a);
//	printf("%d\n", ret);
//	docheck(a);
	fd = open(fname, O_RDWR|O_CREAT, 0666);
	if (fd < 0) {
		fprintf(stderr, "open error:  %s\n", strerror(errno));
		exit(-1);
	}
	int ret = write(fd, buffer, sizeof(buffer));// write something to make sure
																							// file will be deduped
	printf("ret: %d\n", ret);
	if(ret == -1){
		fprintf(stderr, "write error:  %s\n", strerror(errno));
		exit(-1);
	}
	while(1){
		test(fname, fd);
	}
	if (close(fd)) {
		fprintf(stderr, "close error:  %s\n", strerror(errno));
		exit(-1);
	}

	return 0;
}
