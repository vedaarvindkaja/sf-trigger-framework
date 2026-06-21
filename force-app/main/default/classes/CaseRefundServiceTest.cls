/**
 * CaseRefundServiceTest
 * Demonstrates the payoff of the service layer: business logic tested with plain
 * in-memory Cases — no DML, no trigger, no CMDT. Fast and isolated.
 */
@IsTest
private class CaseRefundServiceTest {

    @IsTest
    static void setsRefundOnCancellation() {
        List<Case> cases = new List<Case>{
            new Case(Type = 'Cancellation'),
            new Case(Type = 'Delay'),
            new Case(Type = 'Cancellation', Resolution__c = 'Refund') // already set
        };

        Test.startTest();
        Integer changed = new CaseRefundService().applyRefundOnCancellation(cases);
        Test.stopTest();

        System.assertEquals(1, changed, 'Only the unset cancellation should change.');
        System.assertEquals('Refund', cases[0].Resolution__c);
        System.assertEquals(null, cases[1].Resolution__c, 'Delay untouched.');
    }

    @IsTest
    static void detectsNewlyCancelled() {
        Id idA = TestIds.next(Case.SObjectType);
        Id idB = TestIds.next(Case.SObjectType);

        List<Case> newList = new List<Case>{
            new Case(Id = idA, Type = 'Cancellation'),
            new Case(Id = idB, Type = 'Cancellation')
        };
        Map<Id, Case> oldMap = new Map<Id, Case>{
            idA => new Case(Id = idA, Type = 'Delay'),         // newly cancelled
            idB => new Case(Id = idB, Type = 'Cancellation')    // already was
        };

        Test.startTest();
        Set<Id> result = new CaseRefundService().newlyCancelled(newList, oldMap);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assert(result.contains(idA));
    }
}
