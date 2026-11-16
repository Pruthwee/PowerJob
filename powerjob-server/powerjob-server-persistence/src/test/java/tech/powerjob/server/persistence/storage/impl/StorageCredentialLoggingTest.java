package tech.powerjob.server.persistence.storage.impl;

import tech.powerjob.common.utils.NetUtils;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;

import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.*;

class StorageCredentialLoggingTest {
    private static final String CANARY = "synthetic-credential-canary";

    @Test
    void minioValidationFailureDoesNotDiscloseKeys() {
        assertNoCredential(MinioOssService.class, () -> assertThrows(IllegalArgumentException.class,
                () -> new MinioOssService().initOssClient("http://" + NetUtils.getLoopbackHost() + ":1", "", CANARY, CANARY)));
    }

    @Test
    void aliOssValidationFailureDoesNotDiscloseKeysOrSessionToken() {
        assertNoCredential(AliOssService.class, () -> assertThrows(IllegalArgumentException.class,
                () -> new AliOssService().initOssClient("http://" + NetUtils.getLoopbackHost() + ":1", "", "PWD", CANARY, CANARY, CANARY)));
    }

    @Test
    void mongoInitializationDoesNotLogUriWithCredentials() {
        assertNoCredential(GridFsService.class, () -> {
            GridFsService storage = new GridFsService();
            try {
                storage.initMongo("mongodb://synthetic:" + CANARY + "@" + NetUtils.getLoopbackHost() + ":1/test?serverSelectionTimeoutMS=1");
            } finally {
                storage.destroy();
            }
        });
    }

    @Test
    void mysqlInitializationFailureDoesNotLogCredentialsOrUrl() {
        assertNoCredential(MySqlSeriesDfsService.class, () -> assertThrows(RuntimeException.class,
                () -> new MySqlSeriesDfsService().initDatabase(new MySqlSeriesDfsService.MySQLProperty()
                        .setDriver("synthetic.invalid.Driver").setUrl("jdbc:synthetic://localhost/test?password=" + CANARY)
                        .setUsername(CANARY).setPassword(CANARY))));
    }

    private static void assertNoCredential(Class<?> type, CheckedAction action) {
        Logger logger = (Logger) LoggerFactory.getLogger(type);
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        try {
            action.run();
            String messages = appender.list.stream().map(ILoggingEvent::getFormattedMessage).collect(Collectors.joining("\n"));
            assertFalse(messages.contains(CANARY), "Storage initialization must not log credential canaries");
        } catch (Exception e) {
            fail(e);
        } finally {
            logger.detachAppender(appender);
            appender.stop();
        }
    }

    private interface CheckedAction { void run() throws Exception; }
}
