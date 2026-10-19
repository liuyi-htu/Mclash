/* Controlled forwarding stub for the host JVM JNI integration test only. */
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include "../hev-socks5-tunnel/src/hev-main.h"
#include "../hev-socks5-tunnel/src/hev-jni.h"
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int stopped;
int hev_socks5_tunnel_main(const char *config, int fd)
{
    if (!strcmp(config, "invalid")) return -1;
    pthread_mutex_lock(&gate);
    stopped = 0;
    hev_jni_tunnel_ready();
    if (!strcmp(config, "exit")) {
        pthread_mutex_unlock(&gate);
        usleep(20000);
        return -1;
    }
    while (!stopped) pthread_cond_wait(&changed, &gate);
    pthread_mutex_unlock(&gate);
    return 0;
}
void hev_socks5_tunnel_quit(void)
{
    pthread_mutex_lock(&gate);
    stopped = 1;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&gate);
}
void hev_socks5_tunnel_stats(size_t *a, size_t *b, size_t *c, size_t *d)
{
    *a = *b = *c = *d = 0;
}
