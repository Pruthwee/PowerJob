package tech.powerjob.worker.persistence;

import java.time.Instant;
import tech.powerjob.worker.common.constants.TaskStatus;

import java.nio.charset.StandardCharsets;

/**
 * AbstractTaskDAOTest
 *
 * @author tjq
 * @since 2024/2/4
 */
public class AbstractTaskDAOTest {

    protected static TaskDO buildTaskDO(String taskId, Long instanceId, TaskStatus taskStatus) {
        TaskDO taskDO = new TaskDO();
        taskDO.setTaskId(taskId);
        taskDO.setInstanceId(instanceId);
        taskDO.setSubInstanceId(instanceId);
        taskDO.setTaskName("TEST_TASK");
        taskDO.setTaskContent("TEST_CONTENT".getBytes(StandardCharsets.UTF_8));
        taskDO.setAddress("127.0.0.1:10086");
        taskDO.setStatus(taskStatus.getValue());
        taskDO.setResult("SUCCESS");
        taskDO.setFailedCnt(0);
        taskDO.setLastModifiedTime(Instant.now().toEpochMilli());
        taskDO.setLastReportTime(Instant.now().toEpochMilli());
        taskDO.setCreatedTime(Instant.now().toEpochMilli());
        return taskDO;
    }
}
