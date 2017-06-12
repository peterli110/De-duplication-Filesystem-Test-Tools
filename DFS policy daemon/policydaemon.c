/*
	Dedup policy daemon:
	This program is to monitor DFS partition with inotify
	and dedup old files automatically

	Old files: access time and modify time
						 greater than a specific time

	TODO: 1. add partition space monitor, keep the usage in
				a reasonable range
				2. if a deduped file is accessed frequently,
				restore it automatically
				3. there is an OPEN_MAX for inotify, it
				can't monitor more than 1024 directories
*/
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/inotify.h>
#include <sys/time.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <time.h>
#include <attr/xattr.h>
#include <alloca.h>
#include <errno.h>
#include <stdarg.h>
#include <dirent.h>
#include <linux/limits.h>
#include <limits.h>
#include <signal.h>
#include <sqlite3.h>

#define BUF_LEN (10 * (sizeof(struct inotify_event) + NAME_MAX + 1))
#define HOURS 60 * 60
#define DAYS 60 * 60 * 24

char *logfile = "/tmp/dedupdaemon.log";
char *mdpath = "/tmp/dfsmd";
char *dfs_partition = "/mnt/dfs";
char *dfs_db = "/tmp/dfsmd/dfs.db";
char targetpath[PATH_MAX];
int inotifyFd, wd;
int monitor = IN_ACCESS | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO |
							IN_CREATE | IN_DELETE;

static struct itimerval oldtv;

void write_logs(char *fmt, ...)
{
	char *buffer = alloca(strlen(fmt) + 128);
	FILE *fp = NULL;
	va_list args;
	va_start(args, fmt);

	struct timeval tv;
	struct tm* timeinfo;
	if(gettimeofday(&tv, 0)){
		fprintf(stderr, "gettimeofday error:  %s\n", strerror(errno));
		exit(-1);
	}
	timeinfo = localtime(&tv.tv_sec);
	sprintf(buffer, "[%02d-%02d %02d:%02d:%02d.%03ld]: %s\n",
	timeinfo->tm_mon, timeinfo->tm_mday,
	timeinfo->tm_hour, timeinfo->tm_min,
	timeinfo->tm_sec, tv.tv_usec/1000, fmt);

	fp = fopen(logfile, "a");
	if (fp != NULL){
		vfprintf(fp, buffer, args);
		fflush(fp);
		fclose(fp);
	}
	va_end(args);
}

void write_error(char *fmt, ...)
{
	char *buffer = alloca(strlen(fmt) + 128);
	FILE *fp = NULL;
	va_list args;
	va_start(args, fmt);

	struct timeval tv;
	struct tm* timeinfo;
	if(gettimeofday(&tv, 0)){
		fprintf(stderr, "gettimeofday error:  %s\n", strerror(errno));
		exit(-1);
	}
	timeinfo = localtime(&tv.tv_sec);
	sprintf(buffer, "ERROR: [%02d-%02d %02d:%02d:%02d.%03ld]: %s\n",
	timeinfo->tm_mon, timeinfo->tm_mday,
	timeinfo->tm_hour, timeinfo->tm_min,
	timeinfo->tm_sec, tv.tv_usec/1000, fmt);

	fp = fopen(logfile, "a");
	if (fp != NULL){
		vfprintf(fp, buffer, args);
		fflush(fp);
		fclose(fp);
	}
	va_end(args);
}


void dodedup(char *fname)//use system() to call dfs_cli
{
	char dedup_file[1024] = "../cmd/dfs_cli dedup ";
	strncat(dedup_file, fname, strlen(fname));
	write_logs("deduping file: %s", fname);
	int ret = system(dedup_file);
	if (ret != 0){
		write_error("deduping file: %s", fname);
	}
	else {
		write_logs("deduping file: %s finished", fname);
	}
}

void dorestore(char *fname)//use system() to call dfs_cli
{
	char restore_file[1024] = "../cmd/dfs_cli restore ";
	strncat(restore_file, fname, strlen(fname));
	write_logs("restoring file: %s", fname);
	int ret = system(restore_file);
	if (ret != 0){
		write_error("restoring file: %s", fname);
	}
	else {
		write_logs("restoring file: %s finished", fname);
	}
}

bool isdeduped(char *fname)//check the output of "dfs_cli check"
{
	char check_file[1024] = "../cmd/dfs_cli check ";
	strncat(check_file, fname, strlen(fname));
	FILE *fp;
	char buffer[1024];
	fp=popen(check_file, "r");
	fgets(buffer, sizeof(buffer), fp);
	pclose(fp);


	if (strstr(buffer, "deduped") == NULL){
		write_logs("checking file: %s: NOT deduped", fname);
		return false; //not deduped
	}
	else {
		write_logs("checking file: %s: deduped", fname);
		return true; //deduped
	}
}

//insert stat data to table dfs
void insert_db_dfs(unsigned long inode, char *path, char *atime, char *mtime)
{
	sqlite3 *db;
	char *errMsg = 0;
	char sql[4096];
	int rc;

	rc = sqlite3_open(dfs_db, &db);
	if( rc ) {
		write_error("Can't open database %s: %s\n",
			sqlite3_errmsg(db), strerror(errno));
	}
	sprintf(sql, "INSERT INTO DFS \
								(INODE, PATH, ATIME, MTIME) \
								VALUES (%ju, '%s', '%s', '%s');",
							 	inode, path, atime, mtime);


	rc = sqlite3_exec(db, sql, 0, 0, &errMsg);
	if( rc != SQLITE_OK ){
		write_error("SQL INSERT INTO DFS: %s\n", errMsg);
	 	sqlite3_free(errMsg);
	}
	write_logs("DB WRITTEN: %s file recorded", path);
	sqlite3_close(db);
}

// insert watch descriptor and path into table path
void insert_db_path(int wd, char *path)
{
	sqlite3 *db;
	char *errMsg = 0;
	char sql[4096];
	int rc;

	rc = sqlite3_open(dfs_db, &db);
	if( rc ) {
		write_error("Can't open database %s: %s\n",
			sqlite3_errmsg(db), strerror(errno));
	}
	sprintf(sql, "INSERT INTO PATH \
								(WD, PATH) \
								VALUES (%d, '%s');",
							 	wd, path);


	rc = sqlite3_exec(db, sql, 0, 0, &errMsg);
	if( rc != SQLITE_OK ){
		write_error("SQL INSERT INTO PATH: %s\n", errMsg);
	 	sqlite3_free(errMsg);
	}
	write_logs("DB WRITTEN: wd %d generated, refers to %s", wd, path);
	sqlite3_close(db);
}

// delete by path in table dfs
void delete_db_dfs(char *path)
{
	sqlite3 *db;
	char *errMsg = 0;
	char sql[4096];
	int rc;

	rc = sqlite3_open(dfs_db, &db);
	if( rc ) {
		write_error("Can't open database %s: %s\n",
			sqlite3_errmsg(db), strerror(errno));
	}
	sprintf(sql, "DELETE FROM DFS \
								WHERE PATH='%s';", path);


	rc = sqlite3_exec(db, sql, 0, 0, &errMsg);
	if( rc != SQLITE_OK ){
		write_error("SQL DELETE FROM DFS: %s\n", errMsg);
	 	sqlite3_free(errMsg);
	}
	write_logs("DB DELETE: file %s deleted", path);
	sqlite3_close(db);
}

// delete by wd in table path
void delete_db_path(int wd)
{
	sqlite3 *db;
	char *errMsg = 0;
	char sql[4096];
	int rc;

	rc = sqlite3_open(dfs_db, &db);
	if( rc ) {
		write_error("Can't open database %s: %s\n",
			sqlite3_errmsg(db), strerror(errno));
	}
	sprintf(sql, "DELETE FROM PATH \
								WHERE WD=%d;", wd);


	rc = sqlite3_exec(db, sql, 0, 0, &errMsg);
	if( rc != SQLITE_OK ){
		write_error("SQL DELETE FROM PATH: %s\n", errMsg);
	 	sqlite3_free(errMsg);
	}
	write_logs("DB DELETE: wd %d deleted", wd);
	sqlite3_close(db);
}

// update data in table dfs
void update_db_dfs(char *path, char *atime, char *mtime)
{
	sqlite3 *db;
	char *errMsg = 0;
	char sql[4096];
	int rc;

	rc = sqlite3_open(dfs_db, &db);
	if( rc ) {
		write_error("Can't open database %s: %s\n",
			sqlite3_errmsg(db), strerror(errno));
	}
	sprintf(sql, "UPDATE DFS SET\
								ATIME='%s', MTIME='%s' \
								WHERE PATH='%s';",
							 	atime, mtime, path);


	rc = sqlite3_exec(db, sql, 0, 0, &errMsg);
	if( rc != SQLITE_OK ){
		write_error("SQL UPDATE DFS: %s\n", errMsg);
	 	sqlite3_free(errMsg);
	}
	write_logs("DB UPDATED: %s file recorded", path);
	sqlite3_close(db);
}

// transfer wd to absolute path
// copy path to global variable targetpath
void wd_to_path(int wd)
{
	sqlite3 *db;
	char sql[4096];
	int rc;
	sqlite3_stmt * stmt;

	memset(targetpath, 0, sizeof(targetpath));
	rc = sqlite3_open(dfs_db, &db);
	if( rc ) {
		write_error("Can't open database %s: %s\n",
			sqlite3_errmsg(db), strerror(errno));
	}
	sprintf(sql, "SELECT PATH FROM PATH \
								WHERE WD=%d;", wd);


	rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
	if( rc != SQLITE_OK ){
		write_error("SQL SELECT FROM PATH error");
	}

	if (sqlite3_step(stmt) == SQLITE_ROW) {
		strcpy(targetpath, (char *)sqlite3_column_text(stmt, 0));
		sqlite3_finalize(stmt);
		sqlite3_close(db);
		write_logs("wd_to_path: set wd %d with path %s", wd, targetpath);
	}
	else {
		write_error("wd_to_path: getting wd %d error", wd);
		sqlite3_finalize(stmt);
		sqlite3_close(db);
	}
}

// get old files and dedup
void getfile_handlededup(int seconds) {
	sqlite3 *db;
	char sql[4096];
	char nowtime[64];
	int rc;
	sqlite3_stmt *stmt;

	time_t rawtime;
	struct tm *mytime;
	time(&rawtime);
	mytime = localtime(&rawtime);
	strftime(nowtime, 64, "%s", mytime);

	rc = sqlite3_open(dfs_db, &db);
	if( rc ) {
		write_error("Can't open database %s: %s\n",
			sqlite3_errmsg(db), strerror(errno));
	}
	sprintf(sql, "SELECT PATH FROM DFS \
								WHERE %s-ATIME>%d \
								AND %s-MTIME>%d;",
								nowtime, seconds, nowtime, seconds);


	rc = sqlite3_prepare_v2(db, sql, strlen(sql) + 1, &stmt, NULL);
	if( rc != SQLITE_OK ){
		write_error("SQL SELECT PATH FROM DFS error");
	}

	while(true) {
		int s;

		s = sqlite3_step(stmt);
		if (s == SQLITE_ROW) {
			char *text;
			text = (char *)sqlite3_column_text(stmt, 0);
			if (isdeduped(text) == false) {
				dodedup(text);
			}
		}
		else if (s == SQLITE_DONE) {
			sqlite3_finalize(stmt);
			sqlite3_close(db);
			break;
		}
		else {
			write_error("sqlite3_step failed");
		}
	}
	sqlite3_close(db);
}


//TODO: There is an OPEN_MAX which is 1024 in centos
//This function is to scan the target dir recursively
//If a file is scanned, write into database
//If a dir is scanned, add a inotify_add_watch()
void scanfile_todb(char *name, int level)
{
	DIR *dir;
	struct dirent *dp;
	struct stat statbuf;
	char atime[64];
	char mtime[64];

	if (!(dir = opendir(name))) {
		return;
	}
	if (!(dp = readdir(dir))) {
		return;
	}

	do {
		char path[PATH_MAX + 1];
		snprintf(path, sizeof(path)-1, "%s/%s", name, dp->d_name);

		if (dp->d_type == DT_DIR) {
			if (strcmp(dp->d_name, ".") == 0 || strcmp(dp->d_name, "..") == 0)
					continue;

			wd = inotify_add_watch(inotifyFd, path, monitor);
			if (wd == -1){
				write_error("inotify_add_watch: add path error: %s", path);
			}
			insert_db_path(wd, path);

			scanfile_todb(path, level + 1);
		}

		else {
			if (stat(path, &statbuf) == -1) {
				write_error("stat error: %s\n", strerror(errno));
			}
			strftime(atime, 64, "%s", localtime(&statbuf.st_atime));
			strftime(mtime, 64, "%s", localtime(&statbuf.st_mtime));

			insert_db_dfs((uintmax_t)statbuf.st_ino, path, atime, mtime);
		}
	} while (dp = readdir(dir));
	closedir(dir);
}

// initial database
void init_database(void)
{
	//if db exists, delete it first
	if (access(dfs_db, F_OK) != -1) {
		int rc = unlink(dfs_db);
		if (rc < 0) {
			write_error("delete %s error: %s\n",	dfs_db, strerror(errno));
		}
		write_logs("database exists, deleted");
	}

	sqlite3 *db;
	char *errMsg = 0;
  int rc;
  char *sql;

	rc = sqlite3_open(dfs_db, &db);
	if( rc ) {
		write_error("Can't open database %s: %s\n",
			sqlite3_errmsg(db), strerror(errno));
	} else {
    write_logs("database %s created", dfs_db);
   }

	 sql = "CREATE TABLE DFS("  \
         "INODE INT," \
         "PATH VARCHAR(4096)," \
         "ATIME VARCHAR(64)," \
         "MTIME VARCHAR(64) );" \
				 "CREATE TABLE PATH(" \
				 "WD INT," \
				 "PATH VARCHAR(4096) );";

	 rc = sqlite3_exec(db, sql, 0, 0, &errMsg);
	 if( rc != SQLITE_OK ){
		 write_error("SQL error: %s\n", errMsg);
		 sqlite3_free(errMsg);
   } else {
		 write_logs("Table dfs and path created");
   }
   sqlite3_close(db);
}

// initial inotify
void init_inotify(void)
{
	inotifyFd = inotify_init();
	if (inotifyFd == -1){
		write_error("inotify_init() error");
	}

	wd = inotify_add_watch(inotifyFd, dfs_partition, monitor);
	if (wd == -1){
		write_error("inotify_add_watch: add path error: %s", dfs_partition);
	}
	insert_db_path(wd, dfs_partition);
	scanfile_todb(dfs_partition, 0);
}

// inotify event handler
void inotifyEvent(struct inotify_event *i)
{
	char path[PATH_MAX];

	if (i->mask & (IN_CREATE | IN_MOVED_TO)) {
		//if a dir is created, add a new inotify_add_watch
		if (i->mask & IN_ISDIR) {
			wd_to_path(i->wd);
			sprintf(path, "%s/%s", targetpath, i->name);
			wd = inotify_add_watch(inotifyFd, path, monitor);
			if (wd == -1){
				write_error("inotify_add_watch: add path error: %s", path);
			}
			insert_db_path(wd, path);
		}
		//a normal file created, insert to db
		else {
			struct stat statbuf;
			char atime[64];
			char mtime[64];

			wd_to_path(i->wd);
			sprintf(path, "%s/%s", targetpath, i->name);

			if (stat(path, &statbuf) == -1) {
				write_logs("stat error: %s\n", strerror(errno));
			}
			strftime(atime, 64, "%s", localtime(&statbuf.st_atime));
			strftime(mtime, 64, "%s", localtime(&statbuf.st_mtime));

			insert_db_dfs((uintmax_t)statbuf.st_ino, path, atime, mtime);
		}
	}

	if (i->mask & (IN_DELETE | IN_MOVED_FROM)) {
		//if a dir is deleted
		//delete record in db and watch
		//TODO: free the wd after dir is deleted
		if (i->mask & IN_ISDIR) {
			wd_to_path(i->wd);
			sprintf(path, "%s/%s", targetpath, i->name);
			/*int rc = inotify_rm_watch(inotifyFd, wd);
			if (rc != 0) {
				write_error("inotify_rm_watch error with wd %d", wd);
			}
			else {
				write_logs("inotify_rm_watch: wd %d deleted", wd);
			}*/
			delete_db_path(wd);
		}
		//if a regular file is deleted
		//delete record in db
		else {
			wd_to_path(i->wd);
			sprintf(path, "%s/%s", targetpath, i->name);
			delete_db_dfs(path);
		}
	}

	//If a file is accessed or modified
	//update atime and mtime
	if (i->mask & (IN_ACCESS | IN_MODIFY)) {
		struct stat statbuf;
		char atime[64];
		char mtime[64];

		wd_to_path(i->wd);
		sprintf(path, "%s/%s", targetpath, i->name);

		if (stat(path, &statbuf) == -1) {
			write_logs("stat error: %s\n", strerror(errno));
		}
		strftime(atime, 64, "%s", localtime(&statbuf.st_atime));
		strftime(mtime, 64, "%s", localtime(&statbuf.st_mtime));

		update_db_dfs(path, atime, mtime);
	}

}

void set_timer()
{
    struct itimerval itv;
    itv.it_interval.tv_sec = 20; //timer repeat every 20 seconds
    itv.it_interval.tv_usec = 0;
    itv.it_value.tv_sec = 3; //timer starts after 3 seconds
    itv.it_value.tv_usec = 0;
    setitimer(ITIMER_REAL, &itv, &oldtv);
}

void signal_handler(int m)
{
    getfile_handlededup(1 * HOURS); // dedup files for 1 hour old
}

void run_deamon(void){
	char buf[BUF_LEN] __attribute__ ((aligned(8)));
	ssize_t buffer;
	char *p;
	struct inotify_event *event;

	signal(SIGALRM, signal_handler);
	set_timer();

	while(true) {
		buffer = read(inotifyFd, buf, BUF_LEN);
		if (buffer == 0) {
			write_error("read() from inotify fd returned 0");
		}
		if (buffer == -1) {
			write_error("read()");
		}

		for(p = buf; p < buf + buffer; ) {
			event = (struct inotify_event *) p;
			inotifyEvent(event);
			p += sizeof(struct inotify_event) + event->len;
		}
	}
}

int main(int argc, char *argv[])
{
	int rc;

	init_database();
	init_inotify();
	rc = daemon(0,0);
	if (rc)
		err(EXIT_FAILURE, "daemon() error");

	run_deamon();

	return 0;
}
