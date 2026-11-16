package tech.powerjob.server.remote.worker.utils;

import org.junit.jupiter.api.Test;
import tech.powerjob.server.common.module.WorkerInfo;

import static org.junit.jupiter.api.Assertions.*;

/**
 * SpecifyUtilsTest
 *
 * @author tjq
 * @since 2024/2/24
 */
class SpecifyUtilsTest {

    private static final String WORKER_IP = fixtureIp("TEST_WORKER_IP", 192, 168, 1, 1);
    private static final String OTHER_IP = fixtureIp("TEST_OTHER_IP", 172, 168, 1, 1);

    private static String fixtureIp(String envName, int... octets) {
        String fromEnv = System.getenv(envName);
        if (fromEnv != null && !fromEnv.trim().isEmpty()) {
            return fromEnv.trim();
        }
        return String.format("%d.%d.%d.%d", octets[0], octets[1], octets[2], octets[3]);
    }

    @Test
    void match() {

        WorkerInfo workerInfo = new WorkerInfo();
        workerInfo.setAddress(WORKER_IP);
        workerInfo.setTag("tag1");

        assert SpecifyUtils.match(workerInfo, WORKER_IP);
        assert SpecifyUtils.match(workerInfo, WORKER_IP + ",192.168.1.2,192.168.1.3,192.168.1.4");

        assert !SpecifyUtils.match(workerInfo, OTHER_IP);
        assert !SpecifyUtils.match(workerInfo, OTHER_IP + ",172.168.1.2,172.168.1.3");

        assert SpecifyUtils.match(workerInfo, "tag1");
        assert SpecifyUtils.match(workerInfo, "tag1,tag2");
        assert !SpecifyUtils.match(workerInfo, "t1");
        assert !SpecifyUtils.match(workerInfo, "t1,t2");

        assert SpecifyUtils.match(workerInfo, "tagIn:tag1");
        assert !SpecifyUtils.match(workerInfo, "tagIn:tag2");

        assert SpecifyUtils.match(workerInfo, "tagEquals:tag1");
        assert !SpecifyUtils.match(workerInfo, "tagEquals:tag2");

        workerInfo.setTag("tag1,tag2,tag3");
        assert SpecifyUtils.match(workerInfo, "tagIn:tag1");
        assert SpecifyUtils.match(workerInfo, "tagIn:tag3");
        assert !SpecifyUtils.match(workerInfo, "tagIn:tag99");
    }
}