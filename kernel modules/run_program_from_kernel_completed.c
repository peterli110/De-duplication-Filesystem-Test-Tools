#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/init.h>
#include <linux/kmod.h>
#include <linux/workqueue.h>
#include <linux/moduleparam.h>
#include <linux/stat.h>

MODULE_LICENSE("GPL");

char *program;
module_param(program, charp, S_IRUGO);

static void m_workqueue_function(struct work_struct *data);
static void cancel_work(void);

static DECLARE_DELAYED_WORK(mworkqueue, m_workqueue_function);

static void m_workqueue_function(struct work_struct *data){

  char *argv[3];
  char *envp[] = {
    "HOME=/",
    "TERM=linux",
    "PATH=/sbin:/bin:/usr/sbin:/usr/bin", NULL };
  int ret1;
  bool ret2;

  if (program != NULL){
    argv[0] = program;
  }
  else
    argv [0] = "/usr/bin/touch";
  argv[1] = "/root/testfile";
  argv[2] = NULL;

  ret1 = call_usermodehelper(argv[0], argv, envp, UMH_WAIT_EXEC);
  if (ret1 < 0) {
    printk(KERN_ERR "Program can't be executed\n");
  }
  else {
    ret2 = schedule_delayed_work(&mworkqueue, 3600 * HZ);
    if (ret2 == 0){
      printk(KERN_ERR "schedule_delayed_work failed\n");
    }
  }
}

static int __init init_testmodule(void) {

  bool ret;

  printk(KERN_INFO "Start running program every hour\n");
  ret = schedule_delayed_work(&mworkqueue, 0);
  if (ret == 0){
    printk(KERN_ERR "schedule_delayed_work failed\n");
  }
  return 0;
}

static void __exit exit_testmodule(void) {

  bool ret;

  printk(KERN_INFO "exit testmodule\n");
  ret = cancel_delayed_work_sync(&mworkqueue);
  if (ret == 0)
    printk(KERN_ERR "cancel_delayed_work_sync failed\n");
}

module_init(init_testmodule);
module_exit(exit_testmodule);
