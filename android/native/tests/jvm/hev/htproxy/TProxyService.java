package hev.htproxy;

import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/** Tests JNI_OnLoad, method registration, readiness and real native-to-Java exits. */
public final class TProxyService {
    private static final LinkedBlockingQueue<Integer> exits = new LinkedBlockingQueue<>();
    public native boolean TProxyStartService(String path, int fd);
    public native boolean TProxyStopService();
    public native boolean TProxyIsRunning();
    public native long[] TProxyGetStats();
    public static void tunnelExited(int code) { exits.add(code); }
    private static void check(boolean value) {
        if (!value) throw new AssertionError("JNI lifecycle expectation failed");
    }
    private static void exited(int expectedCode) throws Exception {
        Integer code = exits.poll(2, TimeUnit.SECONDS);
        check(code != null && code == expectedCode);
    }
    public static void main(String[] args) throws Exception {
        System.load(args[0]);
        TProxyService service = new TProxyService();
        for (int cycle = 0; cycle < 20; cycle++) {
            check(!service.TProxyStartService("invalid", 0));
            exited(-1);
            check(!service.TProxyIsRunning());
            check(service.TProxyStopService());
            check(service.TProxyStartService("normal", 0));
            check(service.TProxyIsRunning());
            check(service.TProxyGetStats().length == 4);
            check(!service.TProxyStartService("normal", 0));
            check(service.TProxyStopService());
            exited(0);
            check(!service.TProxyIsRunning());
            check(service.TProxyStopService());
            check(service.TProxyStartService("exit", 0));
            exited(-1);
            check(!service.TProxyIsRunning());
            check(service.TProxyStopService());
        }
        check(exits.isEmpty());
        System.out.println("JNI JVM integration: 20 startup-failure/stop/unexpected-exit cycles and 60 exit callbacks passed");
    }
}
