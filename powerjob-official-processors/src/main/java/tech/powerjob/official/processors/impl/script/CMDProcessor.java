package tech.powerjob.official.processors.impl.script;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;

/**
 * CMDProcessor
 *
 * @author fddc
 * @since 2021/5/14
 */
public class CMDProcessor extends AbstractScriptProcessor {

    @Override
    protected String getScriptName(Long instanceId) {
        return String.format("cmd_%d.bat", instanceId);
    }

    @Override
    protected String getRunCommand() {
        return "cmd.exe";
    }

    @Override
    protected Charset getCharset() {
        return StandardCharsets.UTF_8;
    }
}
