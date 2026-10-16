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
