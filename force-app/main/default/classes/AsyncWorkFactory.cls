/**
 * @description Contract for building the async job associated with a work key.
 *
 * This is the "factory" half of the key-to-factory registry (option A): each
 * Async_Work__mdt record maps a work key to a class implementing this
 * interface. At end of transaction, AsyncDispatcher drains AsyncWorkBuffer,
 * resolves the factory for each pending key via Type.forName, and calls build()
 * to obtain the Queueable to enqueue.
 *
 * Implementations must:
 *  - Expose a zero-argument constructor (required by Type.forName instantiation).
 *  - Be side-effect free in build(): construct and return the job only. Do not
 *    enqueue, publish, or perform DML here — the dispatcher owns those actions.
 */
public interface AsyncWorkFactory {
    /**
     * @description Build the Queueable that processes the given records.
     * @param recordIds The de-duplicated records accumulated for this work key.
     * @return A Queueable ready to be enqueued by the dispatcher.
     */
    System.Queueable build(Set<Id> recordIds);
}
