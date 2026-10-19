/* Host regression harness: real JNI lifecycle code, a controlled forwarding stub.
 * Build: cc -DANDROID -DENABLE_LIBRARY -I$JAVA_HOME/include
 *   -I$JAVA_HOME/include/linux -pthread hev_jni_lifecycle_test.c -o <temp>/hev-jni-test
 * Run under timeout 20s. This does not exercise Android TUN or the network stack.
 */
#include <assert.h>
#include <unistd.h>
#include <stdatomic.h>
#include "../hev-socks5-tunnel/src/hev-jni.c"

static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int release_init, quit_requested, fail_init;
static atomic_int start_finished;

int hev_socks5_tunnel_main(const char *path, int fd)
{
    pthread_mutex_lock(&gate);
    while (!release_init) pthread_cond_wait(&changed, &gate);
    if (!fail_init) {
        hev_jni_tunnel_ready();
        while (!quit_requested) pthread_cond_wait(&changed, &gate);
    }
    pthread_mutex_unlock(&gate);
    return fail_init ? -1 : 0;
}
void hev_socks5_tunnel_quit(void)
{
    pthread_mutex_lock(&gate);
    quit_requested = 1;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&gate);
}
void hev_socks5_tunnel_stats(size_t *a, size_t *b, size_t *c, size_t *d) {}
static const char *get_chars(JNIEnv *env, jstring value, jboolean *copy) { return "test.yml"; }
static void release_chars(JNIEnv *env, jstring value, const char *chars) {}
static const struct JNINativeInterface_ functions = {
    .GetStringUTFChars = get_chars, .ReleaseStringUTFChars = release_chars,
};
static JNIEnv fake_env = &functions;
static void *start_thread(void *arg)
{
    jboolean result = native_start_service(&fake_env, NULL, NULL, 10);
    assert(result == !fail_init);
    atomic_store(&start_finished, 1);
    return NULL;
}
static void reset(int fail)
{
    release_init = quit_requested = 0;
    fail_init = fail;
    atomic_store(&start_finished, 0);
}
int main(void)
{
    pthread_t starter;
    pthread_mutex_init(&mutex, NULL);
    for (int iteration = 0; iteration < 30; ++iteration) {
        reset(iteration % 3 == 0);
        pthread_create(&starter, NULL, start_thread, NULL);
        usleep(10000);
        assert(!atomic_load(&start_finished)); /* pthread_create is not readiness */
        pthread_mutex_lock(&gate);
        release_init = 1;
        pthread_cond_broadcast(&changed);
        pthread_mutex_unlock(&gate);
        pthread_join(starter, NULL);
        if (fail_init) {
            assert(!native_is_running(NULL, NULL));
            assert(!thread_joinable); /* failed startup is reaped */
        } else {
            assert(native_is_running(NULL, NULL));
            assert(!native_start_service(&fake_env, NULL, NULL, 10));
            if (iteration % 2) {
                hev_socks5_tunnel_quit(); /* unexpected forwarding exit */
                pthread_mutex_lock(&state_mutex);
                while (atomic_load(&is_running)) pthread_cond_wait(&state_changed, &state_mutex);
                pthread_mutex_unlock(&state_mutex);
                assert(!native_is_running(NULL, NULL));
            }
        }
        assert(native_stop_service(NULL, NULL));
        assert(native_stop_service(NULL, NULL));
        assert(!thread_joinable && !native_is_running(NULL, NULL));
    }
    puts("Hev JNI lifecycle: 30 failure/start/exit/duplicate-stop/restart cycles passed");
    return 0;
}
