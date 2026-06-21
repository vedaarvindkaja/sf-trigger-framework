/**
 * AppLogger
 * Cross-cutting logging seam. Single choke point for the whole codebase.
 *
 * - info/warn  -> debug log only (cheap, transient).
 * - error      -> debug log AND a rollback-safe persistent record.
 *
 * WHY THE PLATFORM EVENT: if we inserted Error_Log__c directly inside a failing
 * trigger transaction, the rollback would erase the log along with everything
 * else. Error_Event__e is published with PublishImmediately, so it fires the
 * instant we call EventBus.publish() and is NOT undone by a later rollback. A
 * subscriber (LogErrorEventTrigger) then inserts the Error_Log__c in its own
 * transaction. That is the only reliable way to capture the cause of a rollback.
 */
public inherited sharing class AppLogger {
    public enum Level { INFO, WARN, ERROR }

    // ---- simple transient logging -------------------------------------------
    public static void info(String area, String msg) { write(Level.INFO, area, msg); }
    public static void warn(String area, String msg) { write(Level.WARN, area, msg); }

    // ---- error logging: debug + durable -------------------------------------
    public static void error(String area, String msg) {
        write(Level.ERROR, area, msg);
        publish(new ErrorDetail(area, msg, null));
    }

    public static void error(String area, Exception e) {
        write(Level.ERROR, area, e.getMessage() + ' | ' + e.getStackTraceString());
        publish(new ErrorDetail(area, e.getMessage(), e.getStackTraceString()));
    }

    /** Rich overload used by the framework catch blocks. */
    public static void error(ErrorDetail d) {
        write(Level.ERROR, d.context + '/' + d.actionName, d.message);
        publish(d);
    }

    // ---- the durable hop ----------------------------------------------------
    private static void publish(ErrorDetail d) {
        try {
            EventBus.publish(new Error_Event__e(
                Record_Id__c     = d.recordId,
                SObject_Type__c  = d.sObjectType,
                Context__c       = d.context,
                Action_Name__c   = d.actionName,
                Severity__c      = 'Error',
                Message__c       = truncate(d.message, 255),
                Stack_Trace__c   = truncate(d.stackTrace, 255),
                Transaction_Id__c = Request.getCurrent().getRequestId()
            ));
        } catch (Exception pubEx) {
            // Last resort: never let logging throw and mask the real error.
            System.debug(System.LoggingLevel.ERROR,
                '[AppLogger] failed to publish Error_Event__e: ' + pubEx.getMessage());
        }
    }

    private static void write(Level lvl, String area, String msg) {
        System.LoggingLevel s =
            lvl == Level.ERROR ? System.LoggingLevel.ERROR :
            lvl == Level.WARN  ? System.LoggingLevel.WARN  : System.LoggingLevel.INFO;
        System.debug(s, '[' + area + '] ' + msg);
    }

    private static String truncate(String v, Integer max) {
        if (v == null) return null;
        return v.length() > max ? v.substring(0, max) : v;
    }

    /**
     * Structured carrier so callers can pass record context, not just a string.
     * Build with the fluent setters for readability at the call site.
     */
    public class ErrorDetail {
        public String context;
        public String actionName;
        public String message;
        public String stackTrace;
        public String recordId;
        public String sObjectType;

        public ErrorDetail(String context, String message, String stackTrace) {
            this.context = context;
            this.message = message;
            this.stackTrace = stackTrace;
        }
        public ErrorDetail action(String v) { this.actionName = v; return this; }
        public ErrorDetail record(Id v)     { this.recordId = (v == null ? null : String.valueOf(v)); return this; }
        public ErrorDetail sObj(String v)   { this.sObjectType = v; return this; }
    }
}
