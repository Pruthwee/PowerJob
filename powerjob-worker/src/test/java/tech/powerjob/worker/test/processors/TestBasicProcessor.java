package tech.powerjob.worker.test.processors;

import java.time.Instant;
import tech.powerjob.common.serialize.JsonUtils;
import tech.powerjob.worker.core.processor.ProcessResult;
import tech.powerjob.worker.core.processor.TaskContext;
import tech.powerjob.worker.core.processor.sdk.BasicProcessor;

/**
 * 测试用的基础处理器
 *
 * @author tjq
 * @since 2020/3/24
 */
public class TestBasicProcessor implements BasicProcessor {

    @Override
    public ProcessResult process(TaskContext context) throws Exception {
        System.out.println("======== BasicProcessor#process ========");
        System.out.println("TaskContext: " + JsonUtils.toJSONString(context) + ";time = " + Instant.now().toEpochMilli());
        return new ProcessResult(true, Instant.now().toEpochMilli() + "success");
    }


}
