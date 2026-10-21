#include "moonbit.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#if defined(__APPLE__) || defined(__linux__)
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>

/* Every descent uses directory descriptors and rejects links. Readers also
 * reopen the locator and compare identities before returning captured bytes.
 * No renderer-provided absolute path enters these functions. */
#define DEPTH 32
typedef struct { int fd[DEPTH + 2]; struct stat before[DEPTH + 2]; int count; } chain;
static void dispose(chain *c) { while (c->count) close(c->fd[--c->count]); }
static int same(const struct stat *a, const struct stat *b) {
  return a->st_dev == b->st_dev && a->st_ino == b->st_ino;
}
static int unchanged(const struct stat *a, const struct stat *b) {
#ifdef __APPLE__
  return same(a,b) && a->st_size == b->st_size &&
    a->st_mtimespec.tv_sec == b->st_mtimespec.tv_sec && a->st_mtimespec.tv_nsec == b->st_mtimespec.tv_nsec &&
    a->st_ctimespec.tv_sec == b->st_ctimespec.tv_sec && a->st_ctimespec.tv_nsec == b->st_ctimespec.tv_nsec;
#else
  return same(a,b) && a->st_size == b->st_size &&
    a->st_mtim.tv_sec == b->st_mtim.tv_sec && a->st_mtim.tv_nsec == b->st_mtim.tv_nsec &&
    a->st_ctim.tv_sec == b->st_ctim.tv_sec && a->st_ctim.tv_nsec == b->st_ctim.tv_nsec;
#endif
}
static int segment(const char *s) {
  size_t n = strlen(s);
  if (!n || n > 255 || !strcmp(s,".") || !strcmp(s,"..")) return 0;
  return !strchr(s,'\\') && !strchr(s,':');
}
static int descend(int root, const char *path, int directory, chain *c) {
  memset(c,0,sizeof(*c));
  if (strlen(path) > 4096 || path[0]=='/' || strchr(path,'\\') || strchr(path,':')) return 2;
  c->fd[0] = fcntl(root,F_DUPFD_CLOEXEC,0); if (c->fd[0]<0) return 3; c->count=1;
  if (fstat(c->fd[0],&c->before[0])) { dispose(c); return 3; }
  if (!path[0]) { if(directory) return 0; dispose(c); return 2; }
  char copy[4097]; strcpy(copy,path); char *part=copy;
  while (part) {
    char *next=strchr(part,'/'); if(next) *next++=0;
    if (!segment(part) || c->count > DEPTH) { dispose(c); return 2; }
    int flags=O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK;
    if(next || directory) flags |= O_DIRECTORY;
    int fd=openat(c->fd[c->count-1],part,flags);
    if(fd<0) { int code=(errno==ELOOP || errno==ENOTDIR)?4:3; dispose(c); return code; }
    c->fd[c->count]=fd; c->count++;
    struct stat *st=&c->before[c->count-1];
    if(fstat(fd,st)) { dispose(c); return 3; }
    if((next || directory) ? !S_ISDIR(st->st_mode) : (!S_ISREG(st->st_mode) || st->st_nlink!=1)) {
      dispose(c); return 4;
    }
    part=next;
  }
  return 0;
}
static int stable(chain *c, int root, const char *path, int directory) {
  for(int i=0;i<c->count;i++) { struct stat st; if(fstat(c->fd[i],&st)||!unchanged(&st,&c->before[i])) return 6; }
  chain current; int e=descend(root,path,directory,&current); if(e) return 6;
  int ok=current.count==c->count;
  for(int i=0;ok && i<c->count;i++) ok=same(&current.before[i],&c->before[i]);
  dispose(&current); return ok?0:6;
}
static int absolute(const char *path) {
  if(path[0]!='/' || !path[1]) return -2;
  int root=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC); if(root<0)return -3;
  chain c; int e=descend(root,path+1,1,&c); close(root); if(e)return -e;
  int result=c.fd[c.count-1]; c.count--; dispose(&c); return result;
}
#endif

static moonbit_bytes_t packet(int code,const void *data,size_t size) {
  moonbit_bytes_t out=moonbit_make_bytes_raw((int32_t)(size+1)); out[0]=(uint8_t)code;
  if(size)memcpy(out+1,data,size); return out;
}
int32_t morphir_workspace_supported(void) {
#if defined(__APPLE__) || defined(__linux__)
  return 1;
#else
  return 0;
#endif
}
moonbit_bytes_t morphir_workspace_canonical(const char *path) {
#if defined(__APPLE__) || defined(__linux__)
  if(path[0]!='/' || strlen(path)>4096)return packet(2,NULL,0);
  char *resolved=realpath(path,NULL); if(!resolved)return packet(3,NULL,0);
  moonbit_bytes_t out=packet(0,resolved,strlen(resolved));free(resolved);return out;
#else
  return packet(1,NULL,0);
#endif
}
int32_t morphir_workspace_open(const char *path) {
#if defined(__APPLE__) || defined(__linux__)
  return absolute(path);
#else
  return -1;
#endif
}
void morphir_workspace_close(int32_t fd) {
#if defined(__APPLE__) || defined(__linux__)
  if(fd>=0)close(fd);
#endif
}
int32_t morphir_workspace_current(int32_t fd,const char *path) {
#if defined(__APPLE__) || defined(__linux__)
  int now=absolute(path); if(now<0)return 7; struct stat a,b;
  int ok=!fstat(fd,&a)&&!fstat(now,&b)&&same(&a,&b);close(now);return ok?0:7;
#else
  return 1;
#endif
}
moonbit_bytes_t morphir_workspace_list(int32_t root,const char *path) {
#if defined(__APPLE__) || defined(__linux__)
  chain c; int e=descend(root,path,1,&c); if(e)return packet(e,NULL,0);
  int duplicate=openat(c.fd[c.count-1],".",O_RDONLY|O_DIRECTORY|O_CLOEXEC); if(duplicate<0){dispose(&c);return packet(3,NULL,0);}
  DIR *dir=fdopendir(duplicate);if(!dir){close(duplicate);dispose(&c);return packet(3,NULL,0);}
  size_t length=0;unsigned count=0;char *data=malloc(1048576);if(!data){closedir(dir);dispose(&c);return packet(3,NULL,0);}
  struct dirent *entry;
  while(1) {
    errno=0;entry=readdir(dir);if(!entry){if(errno)e=3;break;}
    if(!strcmp(entry->d_name,".")||!strcmp(entry->d_name,".."))continue;
    size_t n=strlen(entry->d_name);if(++count>4096||length+n+2>1048576){e=5;break;}
    if(!segment(entry->d_name)){e=2;break;}
    struct stat st;if(fstatat(dirfd(dir),entry->d_name,&st,AT_SYMLINK_NOFOLLOW)){e=6;break;}
    data[length++]=S_ISLNK(st.st_mode)?'l':S_ISDIR(st.st_mode)?'d':S_ISREG(st.st_mode)?'f':'o';
    memcpy(data+length,entry->d_name,n+1);length+=n+1;
  }
  closedir(dir);if(!e)e=stable(&c,root,path,1);dispose(&c);
  moonbit_bytes_t out=packet(e,e?NULL:data,e?0:length);free(data);return out;
#else
  return packet(1,NULL,0);
#endif
}
moonbit_bytes_t morphir_workspace_read(int32_t root,const char *path,int32_t limit) {
#if defined(__APPLE__) || defined(__linux__)
  if(limit<0||limit>16777216)return packet(5,NULL,0);
  chain c;int e=descend(root,path,0,&c);if(e)return packet(e,NULL,0);
  struct stat *st=&c.before[c.count-1];
  if(st->st_size<0||st->st_size>limit){dispose(&c);return packet(5,NULL,0);}
  size_t size=(size_t)st->st_size,used=0;char *data=malloc(size+1);
  if(!data){dispose(&c);return packet(3,NULL,0);}
  while(used<size+1){ssize_t n=read(c.fd[c.count-1],data+used,size+1-used);if(n<0){if(errno==EINTR)continue;e=3;break;}if(!n)break;used+=(size_t)n;}
  if(!e && used!=size)e=6;if(!e)e=stable(&c,root,path,0);dispose(&c);
  moonbit_bytes_t out=packet(e,e?NULL:data,e?0:size);free(data);return out;
#else
  return packet(1,NULL,0);
#endif
}

/* Writable roots use an independent host-only capability. The packet is built
 * from a bounded host snapshot; renderer paths never reach this entry point
 * without the workspace-file and SourcePath boundaries. */
#if defined(__APPLE__) || defined(__linux__)
#include <stdio.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif
#define FW_LOCK ".morphir-workspace-edit.lock"
#define FW_FILES 4000
#define FW_DIRS 256
#define FW_DATA 16777216U

typedef struct {
  char *path;
  const uint8_t *old_data,*new_data;
  uint32_t old_size,new_size;
  int had_old,has_new,covered,backed,installed,staged_owned,seen;
  struct stat before,staged,backup_version,installed_version;
} fw_file;
typedef struct { char *path; int created,moved,seen; struct stat before; } fw_dir;
typedef struct {
  fw_file *files; fw_dir *creates,*removes,*known;
  uint32_t nf,nc,nr,nk;
  dev_t device;
  int root,lock,plan_owned;
  struct stat plan_version;
} fw_edit;

static int fw_code(void) {
  return errno==ELOOP || errno==ENOTDIR ? 4 : errno==EEXIST || errno==ENOENT ? 6 : 3;
}
static int fw_u32(const uint8_t **p,const uint8_t *end,uint32_t *n) {
  if((size_t)(end-*p)<4)return 2;
  *n=(uint32_t)(*p)[0]|((uint32_t)(*p)[1]<<8)|((uint32_t)(*p)[2]<<16)|((uint32_t)(*p)[3]<<24);*p+=4;return 0;
}
static int fw_path_valid(const char *path) {
  size_t n=strlen(path);if(!n||n>4096||path[0]=='/'||!strcmp(path,FW_LOCK)||!strncmp(path,FW_LOCK"/",strlen(FW_LOCK)+1))return 0;
  char copy[4097];strcpy(copy,path);char *part=copy;unsigned depth=0;
  while(part){char *next=strchr(part,'/');if(next)*next++=0;if(!segment(part)||++depth>16)return 0;
    for(const unsigned char *c=(const unsigned char *)part;*c;c++)if(*c<32||*c==127)return 0;part=next;}
  return 1;
}
static int fw_path(const uint8_t **p,const uint8_t *end,char **out) {
  uint32_t n;int e=fw_u32(p,end,&n);if(e||!n||n>4096||(size_t)(end-*p)<n||memchr(*p,0,n))return 2;
  char *s=malloc(n+1);if(!s)return 3;memcpy(s,*p,n);s[n]=0;*p+=n;
  if(!fw_path_valid(s)){free(s);return 2;}*out=s;return 0;
}
static int fw_within(const char *parent,const char *path) {
  size_t n=strlen(parent);return !strcmp(parent,path)||(!strncmp(parent,path,n)&&path[n]=='/');
}
static int fw_parent(fw_edit *edit,const char *path,chain *c,char leaf[256]) {
  char parent[4097];strcpy(parent,path);char *last=strrchr(parent,'/');
  if(last){strcpy(leaf,last+1);*last=0;}else{strcpy(leaf,parent);parent[0]=0;}
  int e=descend(edit->root,parent,1,c);if(e)return e;
  for(int i=0;i<c->count;i++)if(c->before[i].st_dev!=edit->device){dispose(c);return 4;}
  return 0;
}
static int fw_parent_current(fw_edit *edit,const char *path,chain *expected) {
  chain current;char leaf[256];int e=fw_parent(edit,path,&current,leaf);if(e)return 6;
  int ok=current.count==expected->count;
  for(int i=0;ok&&i<current.count;i++)ok=same(&current.before[i],&expected->before[i]);
  dispose(&current);return ok?0:6;
}
static int fw_sync(chain *c,int lock) {
  for(int i=c->count;i>0;i--)if(fsync(c->fd[i-1]))return 3;
  return fsync(lock)?3:0;
}
static int fw_file_bytes(int fd,const uint8_t *expected,uint32_t size,struct stat *st) {
  if(fstat(fd,st))return 3;
  if(!S_ISREG(st->st_mode)||st->st_nlink!=1)return 4;
  if(st->st_size<0||(uint64_t)st->st_size!=size)return 6;
  uint8_t buffer[8192];uint32_t offset=0;
  while(offset<size){size_t want=size-offset;if(want>sizeof(buffer))want=sizeof(buffer);
    ssize_t n=pread(fd,buffer,want,offset);if(n<0){if(errno==EINTR)continue;return 3;}if(!n||memcmp(buffer,expected+offset,(size_t)n))return 6;offset+=(uint32_t)n;}
  struct stat after;if(fstat(fd,&after))return 3;return unchanged(st,&after)?0:6;
}
static int fw_verify_file(fw_edit *edit,fw_file *file) {
  chain c;int e=descend(edit->root,file->path,0,&c);if(e)return e;
  if(c.before[c.count-1].st_dev!=edit->device){dispose(&c);return 4;}
  e=fw_file_bytes(c.fd[c.count-1],file->old_data,file->old_size,&file->before);
  if(!e)e=stable(&c,edit->root,file->path,0);dispose(&c);return e;
}
static int fw_known_dir(fw_edit *edit,const char *path) {
  for(uint32_t i=0;i<edit->nk;i++)if(!strcmp(edit->known[i].path,path))return (int)i+1;return 0;
}
static fw_file *fw_deleted(fw_edit *edit,const char *path) {
  for(uint32_t i=0;i<edit->nf;i++)if(!strcmp(edit->files[i].path,path)&&edit->files[i].had_old&&!edit->files[i].has_new)return &edit->files[i];return NULL;
}
static int fw_tree(fw_edit *edit,int parent,const char *name,const char *logical,unsigned depth,unsigned *count,int remove_tree) {
  if(depth>16||++*count>4096)return 5;
  struct stat st;if(fstatat(parent,name,&st,AT_SYMLINK_NOFOLLOW))return fw_code();
  if(st.st_dev!=edit->device)return 4;
  if(S_ISREG(st.st_mode)){
    fw_file *file=fw_deleted(edit,logical);if(!file)return 6;
    int fd=openat(parent,name,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);if(fd<0)return fw_code();
    struct stat checked;int e=fw_file_bytes(fd,file->old_data,file->old_size,&checked);close(fd);
    if(e)return e;if(!same(&st,&checked))return 6;file->seen=1;
    if(remove_tree&&unlinkat(parent,name,0))return fw_code();return 0;
  }
  int known=fw_known_dir(edit,logical);
  if(!S_ISDIR(st.st_mode)||!known)return 4;edit->known[known-1].seen=1;
  int fd=openat(parent,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return fw_code();
  struct stat checked;if(fstat(fd,&checked)||!same(&st,&checked)){close(fd);return 6;}
  int duplicate=openat(fd,".",O_RDONLY|O_DIRECTORY|O_CLOEXEC);if(duplicate<0){close(fd);return 3;}
  DIR *directory=fdopendir(duplicate);if(!directory){close(duplicate);close(fd);return 3;}
  int e=0;struct dirent *entry;
  while(1){errno=0;entry=readdir(directory);if(!entry){if(errno)e=3;break;}
    if(!strcmp(entry->d_name,".")||!strcmp(entry->d_name,".."))continue;
    if(!segment(entry->d_name)||strlen(logical)+strlen(entry->d_name)+2>4096){e=2;break;}
    char child[4097];snprintf(child,sizeof(child),"%s/%s",logical,entry->d_name);
    e=fw_tree(edit,fd,entry->d_name,child,depth+1,count,remove_tree);if(e)break;
  }
  closedir(directory);
  if(!e&&!remove_tree){struct stat after;if(fstat(fd,&after)||!unchanged(&checked,&after))e=6;}
  close(fd);if(!e&&remove_tree&&unlinkat(parent,name,AT_REMOVEDIR))e=fw_code();return e;
}
static int fw_verify_tree(fw_edit *edit,int parent,const char *name,const char *logical) {
  for(uint32_t i=0;i<edit->nf;i++)if(fw_within(logical,edit->files[i].path))edit->files[i].seen=0;
  for(uint32_t i=0;i<edit->nk;i++)if(fw_within(logical,edit->known[i].path))edit->known[i].seen=0;
  unsigned count=0;int e=fw_tree(edit,parent,name,logical,1,&count,0);if(e)return e;
  for(uint32_t i=0;i<edit->nf;i++)if(fw_within(logical,edit->files[i].path)&&!edit->files[i].seen)return 6;
  for(uint32_t i=0;i<edit->nk;i++)if(fw_within(logical,edit->known[i].path)&&!edit->known[i].seen)return 6;
  return 0;
}
/* Both supported systems have a no-replace rename. Never fall back to an
 * existence check followed by an overwriting rename. */
static int fw_rename(int source,const char *from,int destination,const char *to) {
#ifdef __APPLE__
  if(renameatx_np(source,from,destination,to,RENAME_EXCL)==0)return 0;
#elif defined(__linux__) && defined(SYS_renameat2)
  if(syscall(SYS_renameat2,source,from,destination,to,1U)==0)return 0;
#else
  errno=ENOSYS;
#endif
  return fw_code();
}
static int fw_name_same(int fd,const char *name,const struct stat *expected) {
  struct stat st;return !fstatat(fd,name,&st,AT_SYMLINK_NOFOLLOW)&&same(&st,expected);
}
static int fw_name_version(int fd,const char *name,const struct stat *expected) {
  struct stat st;return !fstatat(fd,name,&st,AT_SYMLINK_NOFOLLOW)&&unchanged(&st,expected)&&
    st.st_mode==expected->st_mode&&st.st_uid==expected->st_uid&&st.st_gid==expected->st_gid;
}
static int fw_write_stage(fw_edit *edit,fw_file *file,uint32_t index) {
  if(!file->has_new)return 0;char name[32];snprintf(name,sizeof(name),"new-%u",index);
  int fd=openat(edit->lock,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0666);if(fd<0)return fw_code();
  int e=0;if(fstat(fd,&file->staged)){close(fd);return 3;}file->staged_owned=1;
  if(file->had_old&&(fchown(fd,file->before.st_uid,file->before.st_gid)||fchmod(fd,file->before.st_mode&0777)))e=3;
  uint32_t offset=0;while(!e&&offset<file->new_size){ssize_t n=write(fd,file->new_data+offset,file->new_size-offset);
    if(n<0){if(errno==EINTR)continue;e=3;break;}if(!n){e=3;break;}offset+=(uint32_t)n;}
  if(!e&&(fsync(fd)||fstat(fd,&file->staged)))e=3;close(fd);return e;
}
static int fw_plan(fw_edit *edit) {
  int fd=openat(edit->lock,"manifest.tsv",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(fd<0)return fw_code();
  if(fstat(fd,&edit->plan_version)){close(fd);return 3;}edit->plan_owned=1;
  FILE *out=fdopen(fd,"w");if(!out){close(fd);return 3;}
  int e=0;if(fputs("MORPHIR-WORKSPACE-EDIT\t1\n",out)<0)e=3;
  for(uint32_t i=0;!e&&i<edit->nf;i++){
    fw_file *file=&edit->files[i];if(file->covered)continue;
    if(file->had_old&&fprintf(out,"BACKUP\told-%u\t%s\n",i,file->path)<0)e=3;
    if(file->has_new&&fprintf(out,"INSTALL\tnew-%u\t%s\n",i,file->path)<0)e=3;
  }
  for(uint32_t i=0;!e&&i<edit->nr;i++)if(fprintf(out,"DIRECTORY\tdir-%u\t%s\n",i,edit->removes[i].path)<0)e=3;
  for(uint32_t i=0;!e&&i<edit->nc;i++)if(fprintf(out,"PARENT\t-\t%s\n",edit->creates[i].path)<0)e=3;
  if(fflush(out)||fsync(fd)||fstat(fd,&edit->plan_version))e=3;
  if(fclose(out))e=3;if(!e&&(fsync(edit->lock)||fsync(edit->root)))e=3;return e;
}
static int fw_remove_plan(fw_edit *edit) {
  if(!edit->plan_owned)return 0;
  return !fw_name_same(edit->lock,"manifest.tsv",&edit->plan_version)||unlinkat(edit->lock,"manifest.tsv",0)?9:0;
}
static int fw_remove_created(fw_edit *edit) {
  int failed=0;for(uint32_t i=edit->nc;i>0;i--){fw_dir *dir=&edit->creates[i-1];if(!dir->created)continue;
    chain c;char leaf[256];if(fw_parent(edit,dir->path,&c,leaf)){failed=1;continue;}
    if(!fw_name_same(c.fd[c.count-1],leaf,&dir->before)||unlinkat(c.fd[c.count-1],leaf,AT_REMOVEDIR)||fw_sync(&c,edit->lock))failed=1;
    dispose(&c);
  }return failed;
}
static void fw_free(fw_edit *edit) {
  if(edit->files)for(uint32_t i=0;i<edit->nf;i++)free(edit->files[i].path);
  if(edit->creates)for(uint32_t i=0;i<edit->nc;i++)free(edit->creates[i].path);
  if(edit->removes)for(uint32_t i=0;i<edit->nr;i++)free(edit->removes[i].path);
  if(edit->known)for(uint32_t i=0;i<edit->nk;i++)free(edit->known[i].path);
  free(edit->files);free(edit->creates);free(edit->removes);free(edit->known);
}
#endif

int32_t morphir_workspace_lock(int32_t root) {
#if defined(__APPLE__) || defined(__linux__)
  if(mkdirat(root,FW_LOCK,0700))return errno==EEXIST?-8:-3;
  int fd=openat(root,FW_LOCK,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if(fd<0){unlinkat(root,FW_LOCK,AT_REMOVEDIR);return -3;}return fd;
#else
  return -1;
#endif
}
int32_t morphir_workspace_unlock(int32_t root,int32_t lock) {
#if defined(__APPLE__) || defined(__linux__)
  struct stat st;int same_name=!fstat(lock,&st)&&fw_name_same(root,FW_LOCK,&st);close(lock);
  if(!same_name||unlinkat(root,FW_LOCK,AT_REMOVEDIR))return 9;return 0;
#else
  return 1;
#endif
}

int32_t morphir_workspace_apply_files(int32_t root,const uint8_t *packet,int32_t length,int32_t fault) {
#if defined(__APPLE__) || defined(__linux__)
  if(length<20||length>36*1024*1024)return 5;
  const uint8_t *p=packet,*end=packet+length;uint32_t version;fw_edit edit;memset(&edit,0,sizeof(edit));edit.root=root;edit.lock=-1;
  int e=fw_u32(&p,end,&version);if(e||version!=1)return 2;
  if(fw_u32(&p,end,&edit.nf)||fw_u32(&p,end,&edit.nc)||fw_u32(&p,end,&edit.nr)||fw_u32(&p,end,&edit.nk)||edit.nf>FW_FILES||edit.nc>FW_DIRS||edit.nr>FW_DIRS||edit.nk>FW_DIRS)return 5;
  edit.files=calloc(edit.nf?edit.nf:1,sizeof(fw_file));edit.creates=calloc(edit.nc?edit.nc:1,sizeof(fw_dir));
  edit.removes=calloc(edit.nr?edit.nr:1,sizeof(fw_dir));edit.known=calloc(edit.nk?edit.nk:1,sizeof(fw_dir));
  if(!edit.files||!edit.creates||!edit.removes||!edit.known){e=3;goto done;}
  for(uint32_t i=0;i<edit.nf;i++){
    fw_file *file=&edit.files[i];uint32_t n;
    if(fw_u32(&p,end,&n)||!n||n>4096||fw_u32(&p,end,&file->old_size)||fw_u32(&p,end,&file->new_size)||(size_t)(end-p)<n||memchr(p,0,n)){e=2;goto done;}
    file->path=malloc(n+1);if(!file->path){e=3;goto done;}memcpy(file->path,p,n);file->path[n]=0;p+=n;
    if(!fw_path_valid(file->path)){e=2;goto done;}
    for(uint32_t j=0;j<i;j++)if(!strcmp(edit.files[j].path,file->path)){e=2;goto done;}
    file->had_old=file->old_size!=UINT32_MAX;file->has_new=file->new_size!=UINT32_MAX;
    if(!file->had_old&&!file->has_new){e=2;goto done;}
    if(file->had_old){if(file->old_size>FW_DATA||(size_t)(end-p)<file->old_size){e=5;goto done;}file->old_data=p;p+=file->old_size;}
    if(file->has_new){if(file->new_size>FW_DATA||(size_t)(end-p)<file->new_size){e=5;goto done;}file->new_data=p;p+=file->new_size;}
  }
  for(uint32_t i=0;i<edit.nc;i++)if((e=fw_path(&p,end,&edit.creates[i].path)))goto done;
  for(uint32_t i=0;i<edit.nr;i++)if((e=fw_path(&p,end,&edit.removes[i].path)))goto done;
  for(uint32_t i=0;i<edit.nk;i++)if((e=fw_path(&p,end,&edit.known[i].path)))goto done;
  if(p!=end){e=2;goto done;}
  for(uint32_t i=0;i<edit.nr;i++){
    for(uint32_t j=0;j<i;j++)if(fw_within(edit.removes[j].path,edit.removes[i].path)||fw_within(edit.removes[i].path,edit.removes[j].path)){e=2;goto done;}
    for(uint32_t j=0;j<edit.nf;j++)if(fw_within(edit.removes[i].path,edit.files[j].path)){
      if(edit.files[j].has_new){e=2;goto done;}edit.files[j].covered=1;
    }
    for(uint32_t j=0;j<edit.nc;j++)if(fw_within(edit.removes[i].path,edit.creates[j].path)){e=2;goto done;}
  }
  struct stat root_stat;if(fstat(root,&root_stat)||!S_ISDIR(root_stat.st_mode)){e=3;goto done;}edit.device=root_stat.st_dev;
  edit.lock=morphir_workspace_lock(root);if(edit.lock<0){e=-edit.lock;edit.lock=-1;goto done;}
  e=fw_plan(&edit);if(e)goto rollback;
  /* Parent creation is reversible. No existing user file moves until the
   * entire target set and every staged replacement have passed preflight. */
  for(uint32_t i=0;i<edit.nc;i++){
    fw_dir *dir=&edit.creates[i];chain c;char leaf[256];e=fw_parent(&edit,dir->path,&c,leaf);if(e)goto rollback;
    int parent=c.fd[c.count-1];if(mkdirat(parent,leaf,0777)==0)dir->created=1;
    else if(errno!=EEXIST){e=fw_code();dispose(&c);goto rollback;}
    if(fstatat(parent,leaf,&dir->before,AT_SYMLINK_NOFOLLOW)){e=fw_code();dispose(&c);goto rollback;}
    if(!S_ISDIR(dir->before.st_mode)||dir->before.st_dev!=edit.device){e=4;dispose(&c);goto rollback;}
    e=fw_sync(&c,edit.lock);if(e){dispose(&c);goto rollback;}
    dispose(&c);
  }
  for(uint32_t i=0;i<edit.nf;i++){
    fw_file *file=&edit.files[i];
    if(file->had_old){e=fw_verify_file(&edit,file);if(e)goto rollback;}
    else {chain c;char leaf[256];e=fw_parent(&edit,file->path,&c,leaf);if(e)goto rollback;
      struct stat st;if(fstatat(c.fd[c.count-1],leaf,&st,AT_SYMLINK_NOFOLLOW)==0)e=6;else if(errno!=ENOENT)e=fw_code();dispose(&c);if(e)goto rollback;}
    e=fw_write_stage(&edit,file,i);if(e)goto rollback;
  }
  for(uint32_t i=0;i<edit.nr;i++){
    fw_dir *dir=&edit.removes[i];chain c;char leaf[256];e=fw_parent(&edit,dir->path,&c,leaf);if(e)goto rollback;
    if(fstatat(c.fd[c.count-1],leaf,&dir->before,AT_SYMLINK_NOFOLLOW)){e=fw_code();dispose(&c);goto rollback;}
    e=fw_verify_tree(&edit,c.fd[c.count-1],leaf,dir->path);dispose(&c);if(e)goto rollback;
  }
  int steps=0;
  for(uint32_t i=0;i<edit.nr;i++){
    fw_dir *dir=&edit.removes[i];chain c;char leaf[256],backup[32];e=fw_parent(&edit,dir->path,&c,leaf);if(e)goto rollback;
    snprintf(backup,sizeof(backup),"dir-%u",i);
    if(fw_parent_current(&edit,dir->path,&c)||!fw_name_same(c.fd[c.count-1],leaf,&dir->before)){e=6;dispose(&c);goto rollback;}
    e=fw_rename(c.fd[c.count-1],leaf,edit.lock,backup);if(!e)dir->moved=1;
    if(!e)e=fw_sync(&c,edit.lock);
    if(!e)e=fw_parent_current(&edit,dir->path,&c);dispose(&c);if(e)goto rollback;
    if(!fw_name_same(edit.lock,backup,&dir->before)){e=6;goto rollback;}
    e=fw_verify_tree(&edit,edit.lock,backup,dir->path);if(e)goto rollback;
    if((fault>=0&&steps++==fault)||fault==-2){e=3;goto rollback;}
  }
  for(uint32_t i=0;i<edit.nf;i++){
    fw_file *file=&edit.files[i];if(file->covered)continue;chain c;char leaf[256],backup[32],stage[32];
    e=fw_parent(&edit,file->path,&c,leaf);if(e)goto rollback;int parent=c.fd[c.count-1];
    snprintf(backup,sizeof(backup),"old-%u",i);snprintf(stage,sizeof(stage),"new-%u",i);
    e=fw_parent_current(&edit,file->path,&c);if(e){dispose(&c);goto rollback;}
    if(file->had_old){
      if(!fw_name_version(parent,leaf,&file->before)){e=6;dispose(&c);goto rollback;}
      e=fw_rename(parent,leaf,edit.lock,backup);if(e){dispose(&c);goto rollback;}file->backed=1;
      e=fw_sync(&c,edit.lock);if(e){dispose(&c);goto rollback;}
      int fd=openat(edit.lock,backup,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);if(fd<0){e=fw_code();dispose(&c);goto rollback;}
      struct stat st;e=fw_file_bytes(fd,file->old_data,file->old_size,&st);close(fd);if(!e&&!same(&st,&file->before))e=6;
      if(!e&&(st.st_mode!=file->before.st_mode||st.st_uid!=file->before.st_uid||st.st_gid!=file->before.st_gid))e=6;
      if(e){dispose(&c);goto rollback;}file->backup_version=st;
    }
    if(file->has_new){
      if(!fw_name_same(edit.lock,stage,&file->staged)){e=6;dispose(&c);goto rollback;}
      e=fw_rename(edit.lock,stage,parent,leaf);if(e){dispose(&c);goto rollback;}file->installed=1;
      if(!fw_name_same(parent,leaf,&file->staged)||fstatat(parent,leaf,&file->installed_version,AT_SYMLINK_NOFOLLOW)){e=6;dispose(&c);goto rollback;}
      e=fw_sync(&c,edit.lock);if(e){dispose(&c);goto rollback;}
    }
    e=fw_parent_current(&edit,file->path,&c);dispose(&c);if(e)goto rollback;
    if((fault>=0&&steps++==fault)||fault==-2){e=3;goto rollback;}
  }
  /* Backups are retained until every install succeeds. Cleanup never follows a
   * link; unexpected entries preserve the recovery directory. */
  for(uint32_t i=0;i<edit.nf;i++)if(edit.files[i].backed){char name[32];snprintf(name,sizeof(name),"old-%u",i);
    if(!fw_name_version(edit.lock,name,&edit.files[i].backup_version)||unlinkat(edit.lock,name,0)){e=9;goto done;}}
  for(uint32_t i=0;i<edit.nr;i++)if(edit.removes[i].moved){char name[32];snprintf(name,sizeof(name),"dir-%u",i);unsigned count=0;
    if(fw_tree(&edit,edit.lock,name,edit.removes[i].path,1,&count,1)){e=9;goto done;}}
  e=fw_remove_plan(&edit);if(e)goto done;
  e=morphir_workspace_unlock(root,edit.lock);edit.lock=-1;goto done;
rollback:
  {
    int failed=0;
    for(uint32_t i=edit.nf;i>0;i--){fw_file *file=&edit.files[i-1];if(!file->installed)continue;chain c;char leaf[256];
      if(fw_parent(&edit,file->path,&c,leaf)){failed=1;continue;}
      if(!fw_name_version(c.fd[c.count-1],leaf,&file->installed_version)||unlinkat(c.fd[c.count-1],leaf,0)||fw_sync(&c,edit.lock))failed=1;dispose(&c);}
    for(uint32_t i=edit.nf;i>0;i--){fw_file *file=&edit.files[i-1];if(!file->backed)continue;chain c;char leaf[256],name[32];
      if(fault==-2){failed=1;continue;}if(fw_parent(&edit,file->path,&c,leaf)){failed=1;continue;}
      snprintf(name,sizeof(name),"old-%u",i-1);if(fw_rename(edit.lock,name,c.fd[c.count-1],leaf)||fw_sync(&c,edit.lock))failed=1;dispose(&c);}
    for(uint32_t i=edit.nr;i>0;i--){fw_dir *dir=&edit.removes[i-1];if(!dir->moved)continue;chain c;char leaf[256],name[32];
      if(fault==-2){failed=1;continue;}if(fw_parent(&edit,dir->path,&c,leaf)){failed=1;continue;}
      snprintf(name,sizeof(name),"dir-%u",i-1);if(fw_rename(edit.lock,name,c.fd[c.count-1],leaf)||fw_sync(&c,edit.lock))failed=1;dispose(&c);}
    if(fw_remove_created(&edit))failed=1;
    if(failed){e=9;goto done;}
    for(uint32_t i=0;i<edit.nf;i++)if(edit.files[i].staged_owned&&!edit.files[i].installed){char name[32];snprintf(name,sizeof(name),"new-%u",i);
      if(!fw_name_same(edit.lock,name,&edit.files[i].staged)||unlinkat(edit.lock,name,0)){e=9;goto done;}}
    if(fw_remove_plan(&edit)){e=9;goto done;}
    if(morphir_workspace_unlock(root,edit.lock))e=9;edit.lock=-1;
  }
done:
  if(edit.lock>=0)close(edit.lock);fw_free(&edit);return e;
#else
  return 1;
#endif
}
