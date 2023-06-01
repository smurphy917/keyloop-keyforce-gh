trigger ContentVersionAfterUpdate on ContentVersion (after update) {
    for (ContentVersion cv : Trigger.new) {
        ContentVersionHandler.updateCustomerAcceptance(cv);
    }
}