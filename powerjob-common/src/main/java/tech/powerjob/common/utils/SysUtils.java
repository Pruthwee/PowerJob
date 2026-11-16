package tech.powerjob.common.utils;

import org.apache.commons.lang3.StringUtils;
import tech.powerjob.common.PowerJobDKey;
import tech.powerjob.common.enums.SpEnv;

/**
 * 系统工具
 *
 * @author tjq
 * @since 2025/8/17
 */
public class SysUtils {

    /**
     * 可用处理器核数
     * @return 可用处理器核数
     */
    public static int availableProcessors() {
        String property = System.getProperty(PowerJobDKey.SYS_AVAILABLE_PROCESSORS);
        if (StringUtils.isEmpty(property)) {
            // the container's CPU count can be pinned from the environment (e.g. a Kubernetes ConfigMap)
            int fromEnv = envInt("POWERJOB_AVAILABLE_PROCESSORS", 0);
            return fromEnv > 0 ? fromEnv : Runtime.getRuntime().availableProcessors();
        }
        return Integer.parseInt(property);
    }

    /**
     * Read an integer tuning value (thread pool multiplier, queue size...) from an environment variable,
     * so that it can be set per environment (e.g. from a Kubernetes ConfigMap) without rebuilding the image.
     * @param envName environment variable name
     * @param defaultValue value used when the variable is not set
     * @return the configured value
     */
    public static int envInt(String envName, int defaultValue) {
        String value = System.getenv(envName);
        if (StringUtils.isBlank(value)) {
            return defaultValue;
        }
        return Integer.parseInt(value.trim());
    }

    /**
     * 判断是否为测试环境
     * @return 测试环境
     */
    public static boolean isTestEnv() {
        String property = System.getProperty(PowerJobDKey.SP_ENV);
        if (StringUtils.isEmpty(property)) {
            return false;
        }
        return SpEnv.TEST.getCode().equalsIgnoreCase(property);
    }

    /**
     * 判断是否为试用环境
     * @return 试用环境
     */
    public static boolean isTrialEnv() {
        String property = System.getProperty(PowerJobDKey.SP_ENV);
        if (StringUtils.isEmpty(property)) {
            return false;
        }
        return SpEnv.TRIAL.getCode().equalsIgnoreCase(property);
    }
}
