trigger OrderTrigger on Order (after insert) {

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            // OrderTriggerHandler.afterInsert(Trigger.new);
            // No thank you
        }
    }
}