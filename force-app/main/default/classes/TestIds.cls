/**
 * TestIds
 * Generates valid fake SObject Ids for unit tests that need Ids without DML.
 */
@IsTest
public class TestIds {
    private static Integer counter = 1;
    public static Id next(Schema.SObjectType sot) {
        String prefix = sot.getDescribe().getKeyPrefix();
        String body = String.valueOf(counter++).leftPad(12, '0');
        return Id.valueOf(prefix + body);
    }
}
