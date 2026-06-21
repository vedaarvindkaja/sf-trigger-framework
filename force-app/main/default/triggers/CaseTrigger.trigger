trigger CaseTrigger on Case (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    // LANE 1 — single entry. No logic here, ever. Ordering, bypass, recursion
    // control and routing all live below this line. Adding a new object means
    // copying this one line into a new trigger; nothing else changes.
    new MetadataTriggerHandler().run();
}
