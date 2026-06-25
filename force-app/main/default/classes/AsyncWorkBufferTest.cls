/**
 * AsyncWorkBufferTest
 * Unit tests for the transaction-scoped accumulator. No DML required.
 */
@IsTest
private class AsyncWorkBufferTest {

    @IsTest
    static void registerDedupesAndDrains() {
        AsyncWorkBuffer.clear();
        Id a = TestIds.next(Case.SObjectType);
        Id b = TestIds.next(Case.SObjectType);

        AsyncWorkBuffer.register('K', new Set<Id>{ a, b });
        AsyncWorkBuffer.register('K', a); // duplicate must collapse

        System.Assert.isFalse(AsyncWorkBuffer.isEmpty(), 'Buffer holds work.');
        System.Assert.areEqual(new Set<String>{ 'K' }, AsyncWorkBuffer.pendingKeys());

        Set<Id> drained = AsyncWorkBuffer.drain('K');
        System.Assert.areEqual(2, drained.size(), 'Duplicate Id collapses to one entry.');
        System.Assert.isTrue(AsyncWorkBuffer.isEmpty(), 'Drain removes the key.');
        System.Assert.areEqual(0, AsyncWorkBuffer.drain('K').size(), 'Second drain is empty.');
    }

    @IsTest
    static void nullAndBlankAreNoOps() {
        AsyncWorkBuffer.clear();
        AsyncWorkBuffer.register(null, new Set<Id>{ TestIds.next(Case.SObjectType) });
        AsyncWorkBuffer.register('K', (Set<Id>) null);
        AsyncWorkBuffer.register('K', new Set<Id>());
        AsyncWorkBuffer.register('K', (Id) null);
        System.Assert.isTrue(AsyncWorkBuffer.isEmpty(), 'All no-ops leave the buffer empty.');
    }

    @IsTest
    static void singleIdOverloadRegisters() {
        AsyncWorkBuffer.clear();
        Id a = TestIds.next(Case.SObjectType);
        AsyncWorkBuffer.register('K', a);
        System.Assert.areEqual(1, AsyncWorkBuffer.drain('K').size());
    }
}
